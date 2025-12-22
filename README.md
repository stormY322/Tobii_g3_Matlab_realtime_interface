# Tobii Pro Glasses 3 - MATLAB Real-time Interface

This project provides a MATLAB-based interface for the Tobii Pro Glasses 3.  

## Prerequisites  

Before running the code, ensure the following are installed and configured:  

### 1. MATLAB  

- Parallel Computing Toolbox (Required for `parfeval` background tasks).  
- Computer Vision Toolbox (required for scanning arUco markers using `getArUcoMarker`).  

### 2. FFmpeg  

- Must be installed and added to the system's environment variables (PATH).  
- verify by running `ffmpeg -version` in the command line.  

### 3. Hardware  

- Tobii Pro Glasses 3 (connected with PC via Ethernet)  

### 4. Network Verification  

- Before starting MATLAB, open a cmd or PowerShell and run `ping -4 <serial_name>.local`  
- Ensure that a valid IPv4 address can be obtained.  

## Project Structure  

- `experimentConfig.m`  
  - A static singleton class that manages global state (timers, file paths, IP addresses, and sync anchors).
- `tobii_g3_video_receiver.m`  
  - Handles RTSP video streaming, background buffering, and time synchronization.
- `tobii_g3_gazedata_receiver.m`  
  - Handles RTSP data streaming, JSON parsing, and gaze coordinate extraction.
- `arUco_marker_detector.m`
  - Detects AUcon markers, estimates marker coordinates and performs gaze coordinate transformation.

## Usage

### Interface  

- experimentConfig  
A static singleton class that manages global state and time synchronization across different modules.
  - init_fresh_state()  
    - **Description:** Reset and share parameters such as timers and storage paths.  
    - **Usage:** Must be called **once** at the very beginning of main function.
  
- tobii_g3_video_receiver  
Manages the RTSP cideo stream via a background FFmpeg process.  
  - img = get_latest_frame()  
    - **Returns:** a uint8 matrix based on the settings when the object was instantiated.  

- tobii_g3_gazedata_receiver
Handles high-frequency gaze data stream and JSON parsing.
  - gaze = get_gaze_data()
    - **Returns:** [x, y] (1 $\times$ 2 double)  
      - Values are **normalized** (0.0 to 1.0)

- arUco_marker_detector
The computer vision core. It provides two strategies for defining the screen boundary using ArUco markers.
  - basis = getBasisMarker_mean(Image)
    - **Description:** calculates the center point of each of the 4 corner markers.
    - **Returns:** 4 $\times$ 2 matrix [TopLeft; TopRight; BottomLeft; BottomRight] representing the screen corners.
  - basis = getBasisMarker_corner(Image)
    - **Description:** selects the specific outermost corner of each marker (e.g., Top-Left corner of the Top-Left marker).
    - **Returns:** 4 $\times$ 2 matrix [TopLeft; TopRight; BottomLeft; BottomRight].
  - img_transformed = getTransformImage(basis,frame)
    - **Description:** performs a projective transformation to rectify the region defined by the markers, stretching it to fill the entire imge frame.
    - **Inputs:**  
      - basis: A 4 $\times$ 2 matrix containing the detected pixel coordinates of the screen corners.
      - frame: The original video frame.
    - **Outputs:**
      - img_transformed: The rectified image. Returns an empty array if basis contains nan values.
  - point_transformed = getTramsformPoint(basis,frame,x,y)
    - **Description:** maps a specific point (such as a gaze point) from the video coordinate system to the rectified screen coordinate system.
    - **Inputs:**
      - basis: A 4 $\times$ 2 matrix containing the detected pixel coordinates of the screen corners.
      - frame: Used only to reference the target screen dimensions.
      - x,y: The raw pixel coordinates of the point to be transformed.
    - **Outputs:**
      - point_transformed: A 1 $\times$ 2 vector [x_screen, y_screen]. Returns [] if inputs are invalid or basis contains nan.

### Basic Implement  

Do **NOT** run the code as a simple script (`.m` file). You must wrap the main logic inside a **MATLAB Function**.  

``` matlab  
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
            [ids,locs,detectedFamily] = arUco_detector.getArUcoMarker(img);
            basis = arUco_detector.getBasisMarker_corner(ids,locs);
        end

        % display the scene
        if ~isempty(img)
            set(hImg, 'CData', img);
        end

        % display the gaze point
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
```  

## 📂 Output Data Structure

When `save_flag = "true"`, the system automatically generates three synchronized files in the experiment folder.

### 1. `scene_video.mkv`

- **Description**: The raw First-Person View (FPV) video recording from the Tobii Glasses 3 scene camera.
- **Resolution**: 1920 x 1080
- **Framerate**: ~25 fps (Encoded via FFmpeg)
- **Note**: This file serves as the **Time Reference (T=0)** for all CSV timestamps.

---

### 2. `GazeData.csv` (Eye Tracking)

Contains raw gaze coordinates synchronized to the video timeline.

| Column Name | Unit | Range | Description |
| :--- | :--- | :--- | :--- |
| **VideoTime** | Seconds | `0.0` ~ `End` | Time elapsed since video start. **Compensated for transmission latency** (aligned to video events). |
| **GazeX** | Norm | `0.0` ~ `1.0` | Normalized horizontal gaze position. `0` = Left edge, `1` = Right edge. |
| **GazeY** | Norm | `0.0` ~ `1.0` | Normalized vertical gaze position. `0` = Top edge, `1` = Bottom edge. |

> **Note**: `NaN` values in GazeX/GazeY indicate blinks or tracking loss.

---

### 3. `ScreenCorners.csv` (Screen Detection)

Contains the pixel coordinates of the 4 screen corners (ArUco Markers) for every video frame.

| Column Name | Unit | Range | Description |
| :--- | :--- | :--- | :--- |
| **VideoTime** | Seconds | `0.0` ~ `End` | Time elapsed since video start. **Compensated for video buffer delay**. |
| **TL_x / TL_y** | Pixels | `0` ~ `1920/1080` | Coordinates of the **Top-Left** screen corner (Marker ID 1). |
| **TR_x / TR_y** | Pixels | `0` ~ `1920/1080` | Coordinates of the **Top-Right** screen corner (Marker ID 2). |
| **BL_x / BL_y** | Pixels | `0` ~ `1920/1080` | Coordinates of the **Bottom-Left** screen corner (Marker ID 3). |
| **BR_x / BR_y** | Pixels | `0` ~ `1920/1080` | Coordinates of the **Bottom-Right** screen corner (Marker ID 5). |

> **Note**: If a marker is occluded (e.g., by a hand), its coordinates will be recorded as `NaN`.

---

### 📊 Coordinate Systems

- **Video Frame**: Top-Left is `(0, 0)`, Bottom-Right is `(1920, 1080)`.
- **Gaze Data**: Top-Left is `(0.0, 0.0)`, Bottom-Right is `(1.0, 1.0)`.
- **Conversion Formula**:

    ```matlab

    Pixel_X = GazeX * 1920
    Pixel_Y = GazeY * 1080
    ```  
# Tobii_g3_Matlab_realtime_interface
