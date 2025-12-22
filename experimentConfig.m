classdef experimentConfig
    methods (Static)
        function init_fresh_state()
            experimentConfig.manage_central_state('reset');
            disp(">>> [System] State Initialized (Counter=0)");
        end
        function activate_session()
            current_count = experimentConfig.manage_central_state('get_count');
            
            if current_count == 0
                disp(">>> [Start] First object activated. Resetting Folder & Time.");
                experimentConfig.reset_folder_and_time();
            end
            
            new_count = experimentConfig.manage_central_state('inc_count');
            disp("activate active_counter is " + int2str(new_count));
        end

        function deactive_session()

            new_count = experimentConfig.manage_central_state('dec_count');
            disp("disactivate active_counter is " + int2str(new_count));
            
            if new_count == 0
                disp(">>> [End] All objects deactivated. Session Over.");
            end
        end

        function folder_name = get_current_folder()
           [folder_name, ~] = experimentConfig.manage_central_state('get_data');
        end
        
        function timestamp = get_current_time()
            [~, timestamp] = experimentConfig.manage_central_state('get_data');
        end

        function ip = get_device_ip()
            ip = experimentConfig.manage_central_state('get_IP');
        end

        function set_device_IP (ip)
            experimentConfig.manage_central_state('set_IP',ip);
        end

        function set_video_start_time(t)
            experimentConfig.manage_central_state('set_v_start', t);
        end
        
        function t = get_video_start_time()
            t = experimentConfig.manage_central_state('get_v_start');
        end
    end
    
    methods (Static, Access = private)
        
        function reset_folder_and_time()
            base_dir = fileparts(mfilename("fullpath")); 
            timestamp = string(datetime('now','Format','yyyyMMdd_HHmmss'));
            new_path = fullfile(base_dir, timestamp);
            
            if ~exist(new_path, 'dir')
                mkdir(new_path);
            end
            
            new_tic = tic;
            
            experimentConfig.manage_central_state('set_data', new_path, new_tic);
        end


        function [out1, out2] = manage_central_state(action, varargin)
            persistent active_counter stored_path start_time device_ip video_start_time
            
            if isempty(active_counter), active_counter = 0; end
            if isempty(stored_path), stored_path = pwd; end
            if isempty(start_time), start_time = tic; end
            
            out1 = []; out2 = [];
            
            switch action
                case 'reset'
                    active_counter = 0;
                    stored_path = [];
                    start_time = [];
                    device_ip = [];
                    video_start_time = [];

                case 'get_count'
                    out1 = active_counter;
                    
                case 'inc_count'
                    active_counter = active_counter + 1;
                    out1 = active_counter;
                    
                case 'dec_count'
                    if active_counter > 0
                        active_counter = active_counter - 1;
                    end
                    out1 = active_counter;
                    
                case 'set_data'
                    stored_path = varargin{1};
                    start_time  = varargin{2};
                    
                case 'get_data'
                    out1 = stored_path;
                    out2 = toc(start_time);
                
                case 'get_ip'
                    out1 = device_ip;

                case 'set_ip'
                    device_ip = varargin{1};
                    
                case 'set_v_start'
                    video_start_time = varargin{1};

                case 'get_v_start'
                    out1 = video_start_time;
            end
        end
    end
end