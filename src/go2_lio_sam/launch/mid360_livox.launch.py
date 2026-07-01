import os
from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch_ros.actions import Node

# CustomMsg (xfer_format=1)，由 livox_custom_to_pc2 转为 PointCloud2 供 LIO-SAM
xfer_format = 1
multi_topic = 0
data_src = 0
publish_freq = 10.0
output_type = 0
frame_id = 'livox_frame'

go2_share = get_package_share_directory('go2_lio_sam')
user_config_path = os.path.join(go2_share, 'config', 'MID360_config_go2.json')
if not os.path.isfile(user_config_path):
    livox_share = get_package_share_directory('livox_ros_driver2')
    user_config_path = os.path.join(livox_share, 'config', 'MID360_config_test.json')

livox_ros2_params = [
    {"xfer_format": xfer_format},
    {"multi_topic": multi_topic},
    {"data_src": data_src},
    {"publish_freq": publish_freq},
    {"output_data_type": output_type},
    {"frame_id": frame_id},
    {"user_config_path": user_config_path},
    {"cmdline_input_bd_code": 'livox0000000001'},
]


def generate_launch_description():
    return LaunchDescription([
        Node(
            package='livox_ros_driver2',
            executable='livox_ros_driver2_node',
            name='livox_lidar_publisher',
            output='screen',
            parameters=livox_ros2_params,
        ),
    ])
