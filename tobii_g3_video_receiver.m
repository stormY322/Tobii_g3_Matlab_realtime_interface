% tobii_g3_streamer_async
% 构造函数 给初始参数赋值 定义共享内存空间 开启后台读取流数据的程序 输入：眼镜序列号，希望获得数据所处的流，灰度还是rgb图像
% 后台读取流数据的函数 输入：ipv4地址，流编号，图像格式 无输出：获得的图像保存在内存中
% 获得ipv4地址函数 输入：眼镜序列号 输出：ipv4地址
% 析构函数 关闭流 释放空间
% 获得图像函数 输出图像数据



classdef tobii_g3_video_receiver < handle
    properties (Access = private)
        width = 1920;
        height = 1080;
        color_channel;
        framesize;
        save_flag;
        shared_file_name;
        shared_memory;
        stop_flag_file;
        future_result;
        Queue;
    end
    
    methods (Access = public)
        function obj = tobii_g3_video_receiver(tobii_serial, save_flag, selected_channel, video_type)

            if(nargin == 1)
                save_flag = "false";
                selected_channel = 0;
                video_type = "rgb24";
            elseif(nargin == 2)
                selected_channel = 0;
                video_type = "rgb24";
            elseif (nargin == 3)
                video_type = "rgb24";
            end
            
            obj.save_flag = save_flag;
            
            fullpath = "";
            if lower(save_flag) == "true"
                experimentConfig.activate_session(); 
                save_dir = experimentConfig.get_current_folder();
                fullpath = fullfile(save_dir, "scene_video.mkv");
            end
            
            switch (video_type)
                case "rgb24"
                    obj.color_channel = 3;
                case "gray"
                    obj.color_channel = 1;
            end
        
            obj.Queue = parallel.pool.DataQueue;
            afterEach(obj.Queue, @(msg) fprintf('worker: %s\n', msg));
            
            ipv4_address = obj.get_tobii_ip(tobii_serial);
            
            obj.framesize = obj.width * obj.height * obj.color_channel;
            obj.shared_file_name = fullfile(tempdir, "tobii_frame_buffer.bin");
            obj.stop_flag_file = fullfile(tempdir, "tobii_stop.flag");
            
            if isfile(obj.stop_flag_file), delete(obj.stop_flag_file); end 
            

            total_bytes = 1 + obj.framesize; 
            fileID = fopen(obj.shared_file_name, "w");
            fwrite(fileID, zeros(total_bytes, 1), 'uint8'); 
            fclose(fileID);
            
            obj.shared_memory = memmapfile(obj.shared_file_name, 'Writable', true, ...
                'Format', {'uint8', [1 1], 'NewFlag'; 'uint8', [obj.framesize, 1], 'ImageRaw'});
            
            disp("Start background collection process.");
            
            obj.future_result = parfeval(@tobii_g3_video_receiver.background_task, 0, ...
                ipv4_address, obj.width, obj.height, selected_channel, video_type, ...
                obj.shared_file_name, obj.stop_flag_file, obj.Queue, obj.save_flag, fullpath);
            

            disp(">>> [Video] Waiting for the first frame to sync time anchor...");
            
            max_wait_time = 10; 
            start_wait = tic;
            frame_arrived = false;
            
            while toc(start_wait) < max_wait_time

                current_flag = obj.shared_memory.Data.NewFlag;
                
                if current_flag > 0
                    t_anchor = experimentConfig.get_current_time();
                    experimentConfig.set_video_start_time(t_anchor);
                    
                    frame_arrived = true;
                    fprintf(">>> [Sync] First frame detected! Video Anchor set at: %.4f s\n", t_anchor);
                    break;
                end
                
                pause(0.05);
            end
            
            if ~frame_arrived
                warning(">>> [Video] Timeout! Video stream did not start within 10 seconds. Sync anchor NOT set.");
            end
            
            disp("Background collection process is running.");
        end
        
        function img = get_latest_frame(obj)
            raw_data = obj.shared_memory.Data.ImageRaw;
            
            temp = reshape(raw_data, [obj.color_channel, obj.width, obj.height]);
            img = permute(temp, [3, 2, 1]);
        end
        
        function delete(obj)
            disp ("Finishing background process.");
            

            fclose(fopen(obj.stop_flag_file, "w"));
            
            if ~isempty (obj.future_result)
                try
                    wait(obj.future_result, 'Finished', 2);
                    cancel(obj.future_result);
                catch
                    
                end
            end
            

            clear obj.shared_memory;
            delete(obj.Queue);
            
            if isfile(obj.shared_file_name), delete(obj.shared_file_name); end
            if isfile(obj.stop_flag_file), delete(obj.stop_flag_file); end
            

            experimentConfig.deactive_session();
            disp("Finished closing.")
        end
    end
    
    methods (Static, Access = private)
        function background_task(ipv4_address, width, height, selected_channel, video_type, shared_file_name, stop_flag_file, q, save_flag, fullpath)

            switch (video_type)
                case "rgb24"
                    color_channel = 3;
                case "gray"
                    color_channel = 1;
            end
            
            frame_size = width * height * color_channel;
            rtsp_url = strcat("rtsp://", ipv4_address, ":8554/live/all");
            
            ffmpeg_cmd_to_save = "";
            if lower(save_flag) == "true"

                ffmpeg_cmd_to_save = strcat(" -map 0:", int2str(selected_channel), " -c:v copy -y ", fullpath);
            end
            

            ffmpeg_cmd = strcat("ffmpeg ", ...
                " -fflags nobuffer", ...           % [关键] 禁用接收缓冲区，降低延迟
                " -flags low_delay", ...           % [关键] 告诉解码器尽快输出，不要等B帧
                " -rtsp_transport tcp", ...        % [稳定] 强制使用 TCP (防止 UDP 丢包花屏)
                " -i ", rtsp_url, ...              % 输入源
                ffmpeg_cmd_to_save, ...            % 保存命令(如果有)
                " -map 0:", int2str(selected_channel), ...
                " -f rawvideo -pix_fmt ", video_type, " -"); % 输出到管道
                
            send(q, "ffmpeg command: " + ffmpeg_cmd);
            

            process = java.lang.ProcessBuilder(strsplit(ffmpeg_cmd)).start();
            channel = java.nio.channels.Channels.newChannel(process.getInputStream());
            buffer = java.nio.ByteBuffer.allocate(frame_size);
            

            m = memmapfile(shared_file_name, "Writable", true, ...
                'Format', {'uint8', [1 1], 'NewFlag'; 'uint8', [frame_size, 1], 'ImageRaw'});
                
            send(q, 'Start collecting frames.');
            counter = 0;
            
            while true
 
                if isfile(stop_flag_file)
                    break;
                end
                
                buffer.clear();
                

                while buffer.hasRemaining()
                    count = channel.read(buffer);
                    if count == -1, break; end
                end
                if count == -1, break; end 
                

                m.Data.ImageRaw = typecast(int8(buffer.array()), "uint8");
                
                counter = counter + 1;
                m.Data.NewFlag = uint8(mod(counter, 255)); 
            end
            
            process.destroy();
            send(q, "Exiting.")
        end
    end
    
    methods (Access = private)
        function ip_address = get_tobii_ip(obj, serial_number)
            shared_ip = experimentConfig.get_device_ip();
            
            if ~isempty (shared_ip)
                ip_address = shared_ip;
            else
                disp(['Pinging device: ', serial_number, '.local ...']);
                cmd = strcat("ping -4 ", serial_number, ".local");
                [status, cmdout] = system(cmd);
                
                if status ~= 0
                    error(['The ping request could not find the host ' serial_number '. Please check connection.']);
                end
    
                pattern = '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}';
                match = regexp(cmdout, pattern, 'match');
    
                if ~isempty(match)
                    ip_address = match{1};
                    disp(['Successfully acquired IP: ' ip_address]);

                    experimentConfig.set_device_IP(ip_address);
                else
                    error('The glasses are connected, but no valid IP was found in ping output.');
                end
            end
        end
    end
end