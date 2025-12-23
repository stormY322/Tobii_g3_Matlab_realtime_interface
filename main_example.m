main_function();
function main_function()
    
    % Initialize
    skip_num = 5;
    timer = 0;
    experimentConfig.init_fresh_state();
    serial_number = "TG03B-080201027461";
    width = 1920;
    height = 1080;

    % Instantiate objects
    video_receiver = tobii_g3_video_receiver(serial_number,"true"); % set the second parameter as "true" to save the data.
 
    gaze_data_receiver = tobii_g3_gazedata_receiver(serial_number,"true"); % set the second parameter as "true" to save the data.
    arUco_detector = arUco_marker_detector(width, height, "true"); % set the third parameter as "true" to save the data.


    figure('Name', 'Realtime', 'NumberTitle', 'off', 'MenuBar', 'none');
    
    % 'YDir', 'reverse' is necessary, otherwise the image and the fixation point will be upside down
    hAx = axes('Position', [0 0 1 1], 'YDir', 'reverse');
    
    % Lock coordinate range (to prevent the axes from automatically scaling when the red dot goes out of bounds)
    axis(hAx, [0 width 0 height]);
    axis(hAx, 'off'); 
    hold(hAx, 'on');  
    

    hImg = image(zeros(height, width, 3, 'uint8'), 'Parent', hAx);
    
    hGaze = plot(hAx, -100, -100, 'ro', ...
                 'MarkerSize', 10, ...
                 'LineWidth', 3);
    drawnow; 
    gaze_point = zeros(2,1);

    while ishandle(hImg)
        timer = timer + 1;

        img = video_receiver.get_latest_frame();
        gaze_data = gaze_data_receiver.get_gaze_data();
        
        % Skip frames to achieve better performance
        if mod(timer,skip_num) == 0
            basis = arUco_detector.getBasisMarker_corner(img);
        end

        % display the scene
        if ~isempty(img)
            set(hImg, 'CData', img);
        end

        % disp play the gaze point
        if ~isempty(gaze_data) && ~isnan(gaze_data(1))
            gaze_point(1) = gaze_data(1)*width;
            gaze_point(2) = gaze_data(2)*height;
            set(hGaze, 'XData', gaze_point(1), 'YData', gaze_point(2), 'Visible', 'on');
        end        
        drawnow limitrate;

    end
    toc
    disp('Shutting down the device and saving data...');
    
    delete(gaze_data_receiver); 
    
    delete(video_receiver);     
    
    delete(hImg);
    disp('[Success] All data has been saved.');
end