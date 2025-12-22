classdef arUco_marker_detector < handle
    properties (Access = private)
        screen_resolution;
        ref_points;
        save_flag;
        data_save_file;
        datalog;
        logindex;
        max_samples = 200000;
    end
    properties (Access = public)
        TargetsFamilyID = [1,2,3,5];
        TargetsCorners = [1,2,4,3];
    end
    methods (Access = public)
        function obj = arUco_marker_detector(width, height, save_flag)
            if nargin <3
                save_flag = "false";
            end
            obj.save_flag = save_flag;
            obj.screen_resolution = [width, height];
            obj.ref_points = [0,0; width,0; 0,height; width,height];
            obj.logindex = 0;
            if lower(obj.save_flag) == "true"
                experimentConfig.activate_session();
                save_dir = experimentConfig.get_current_folder();
                obj.data_save_file = fullfile(save_dir, "ScreenCorners.csv");
                obj.datalog = nan(obj.max_samples, 9);
            end
        end

        function basis = getBasisMarker_mean(obj,Image)
            [ids, locs, detectedFamily] = readArucoMarker(Image);
            basis = nan(4,2);
            if ~isempty(ids)
                for i = 1:4
                    basis(i,:) = obj.getMarkerMean(ids,locs,obj.TargetsFamilyID(i));
                end
            end
            if lower(obj.save_flag) == "true"
                obj.log_marker_data(basis);
            end
        end

        function basis = getBasisMarker_corner(obj,Image)
            [ids, locs, detectedFamily] = readArucoMarker(Image);
            basis = nan(4,2);
            if ~isempty(ids)
                for i = 1:4
                    basis(i,:) = obj.getMarkerCorner(ids,locs,obj.TargetsFamilyID(i),obj.TargetsCorners(i));
                end
            end
            if lower(obj.save_flag) == "true"
                obj.log_marker_data(basis);
            end
        end

        function img_transformed = getTransformImage(obj,basis,frame)
            target_x = size(frame,2);
            target_y = size(frame,1);
            r = imref2d([target_y,target_x]);
            target = [0,0;target_x,0;0,target_y;target_x,target_y];
            img_transformed = [];
            if any(isnan(basis(:)))
                return;
            end
            trans_mat = fitgeotform2d(basis,target,"projective");
            img_transformed = imwarp(frame,trans_mat,"OutputView",r);
        end

        function point_transformed = getTransformPoint(obj,basis,frame,x,y)
            target_x = size(frame,2);
            target_y = size(frame,1);
            target = [0,0; target_x,0; 0,target_y;target_x,target_y];
            point_transformed = [];
            if any(isnan(basis(:))) || isnan(x) || isnan(y)
                return;
            end
            tform = fitgeotform2d(basis,target,"projective");
            point_transformed = transformPointsForward(tform,x,y);
        end

        function delete(obj)
            if lower(obj.save_flag) == "true" && obj.logindex > 0 
                raw_data = obj.datalog(1:obj.logindex,:);
                video_start_t = experimentConfig.get_video_start_time();
                aligned_time = (raw_data(:, 1) - video_start_t-1);
                
                SaveData = [aligned_time, raw_data(:, 2:end)];
                col_names = {'VideoTime', 'TL_x', 'TL_y', 'TR_x', 'TR_y', 'BL_x', 'BL_y', 'BR_x', 'BR_y'};
                T = array2table(SaveData, 'VariableNames', col_names);
                writetable(T, obj.data_save_file);
                experimentConfig.deactive_session();
            end
        end
    end
    methods (Access = private)
        function markerPosition = getMarkerMean(obj,ids,locs,family_index)
            markerPosition = [nan, nan];
            idx = find(ids == family_index, 1);
            if ~isempty(idx)
                corners = squeeze(locs(idx, :, :));
                markerPosition = mean(corners,1);
            end
        end

        function markerPosition = getMarkerCorner(obj,ids,locs,family_index,corner_index)
            markerPosition = [nan, nan];
            idx = find(ids == family_index, 1);
            if ~isempty(idx)
                corners = squeeze(locs(:,:,idx));
                if corner_index >=1 && corner_index <= 4
                    markerPosition = squeeze(corners(corner_index,:));
                end
            end
        end
        function log_marker_data(obj, basis)
            if obj.logindex >= obj.max_samples
                return;
            end
            
            t_now = experimentConfig.get_current_time();
            obj.logindex = obj.logindex + 1;
            
            flat_basis = reshape(basis', 1, 8);

            obj.datalog(obj.logindex, :) = [t_now, flat_basis];
        end
    end
end