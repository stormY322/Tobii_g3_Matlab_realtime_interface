classdef tobii_g3_gazedata_receiver < handle
    properties (Access = private)
        process;
        reader;
        charbuffer;
        save_flag;
        databuffer = "";
        data_save_file;
        datalog;
        logindex;
    end
    methods (Access = public)
        function obj = tobii_g3_gazedata_receiver(tobii_serial,save_flag,selected_channel)
            if (nargin ==1)
                save_flag = "false";
                selected_channel = 3;
            elseif(nargin == 2)
                selected_channel = 3;
            end
            
            obj.save_flag = save_flag;

            if lower(obj.save_flag) == "true"
                experimentConfig.activate_session();
                obj.start_Recording();
            end
            ipv4_address = obj.get_tobii_ip(tobii_serial);
            rtsp_url = strcat("rtsp://",ipv4_address,":8554/live/all");
            ffmpeg_cmd = strcat("ffmpeg ","-rtsp_transport tcp"," -flags low_delay ","-i ",rtsp_url," -map 0:",int2str(selected_channel)," -f data ","-");
            disp(ffmpeg_cmd);
            obj.process = java.lang.ProcessBuilder(strsplit(ffmpeg_cmd)).start();
            inputStream = obj.process.getInputStream();
            obj.reader = java.io.BufferedReader(java.io.InputStreamReader(inputStream));
            obj.charbuffer = java.nio.CharBuffer.allocate(2048);
        end


        function gaze = get_gaze_data(obj)
            gaze = [];
            if obj.reader.ready()
                n = obj.reader.read(obj.charbuffer);
                
                arrival_time = experimentConfig.get_current_time()-experimentConfig.get_video_start_time();
                if n>0
                    obj.charbuffer.flip();
                    raw_str = char(obj.charbuffer.toString());
                    obj.charbuffer.clear();
                    obj.databuffer = obj.databuffer + string(raw_str);
                    gaze = obj.processing_json_data();
                    data_new_num = size(gaze,1);
                    if obj.logindex+data_new_num <= size(obj.datalog,1)
                        start_index= obj.logindex + 1;
                        end_index = obj.logindex + data_new_num;
                        data_time = repmat(arrival_time,data_new_num,1);
                        obj.datalog(start_index:end_index,:) = [data_time,gaze];
                        obj.logindex = end_index;
                    end

                    if ~isempty(gaze)
                        gaze=gaze(end,:);
                    end
                end
            end
        end
        function delete(obj)
            if ~isempty(obj.process)
                obj.process.destroy();
                experimentConfig.deactive_session();
                if lower(obj.save_flag) =="true"
                    valid_data = obj.datalog(1:obj.logindex,:);
                    disp(size(valid_data));
                    GazeTable = array2table(valid_data, ...
                        'VariableNames', {'Time', 'GazeX', 'GazeY'});
                    writetable(GazeTable, obj.data_save_file);
                end
            end
        end
    end

    methods (Access = private)
        function start_Recording(obj)
            save_dir = experimentConfig.get_current_folder();
            obj.data_save_file = fullfile(save_dir,"GazeData.csv");
            obj.datalog = nan(360000,3);
            obj.logindex = 0;
        end
        function ip_address = get_tobii_ip(obj,serial_number)

            shared_ip = experimentConfig.get_device_ip();

            if ~isempty (shared_ip)
                ip_address = shared_ip;
            else
                cmd = strcat("ping -4 ",serial_number,".local");
                [status, cmdout] = system(cmd);
                if status ~= 0
                    error('The ping request could not find the host '+serial_number+'. Please check the name and try again');
                end
    
                pattern = '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}';
                match = regexp(cmdout, pattern, 'match');
    
                if ~isempty(match)
                    ip_address = match{1};
                    disp(['Successfully acquired IP address! Current IP address: ' ip_address]);
                    experimentConfig.set_device_IP(ip_address);
                else
                    error('The glasses are connected, but no valid IP was found.');
                end
            end
        end

        function gaze_batch = processing_json_data(obj)
            gaze_batch = zeros(0,2);
            clean_str = strrep(obj.databuffer, "}{", "}" + newline + "{");
            parts = split(clean_str, newline);
            if length(parts) < 2
                return;
            end
            obj.databuffer = parts(end);

            parts_to_process = parts(1:length(parts)-1);

            mask = startsWith(parts_to_process, "{") & (strlength(parts_to_process) > 1);
            parts_complete = parts_to_process(mask);

            if isempty(parts_complete)
                return;
            end

            json_str_array = "["+join(parts_complete,",") + "]";
            json_cell = jsondecode(json_str_array);

            extract_fn = @(x) obj.get_gaze_or_nan(x);
            if isstruct(json_cell)
                json_cell = num2cell(json_cell);
            end
            result_cell = cellfun(extract_fn,json_cell,'UniformOutput',false);
            gaze_batch = cell2mat(result_cell')';
        end

        function val = get_gaze_or_nan(obj, s)
            if isstruct(s) && isfield(s, 'gaze2d') && ~isempty(s.gaze2d)
                val = s.gaze2d; % 返回 2x1 double
            else
                val = [NaN; NaN]; % 返回 2x1 NaN (占位)
            end
        end
    end
end