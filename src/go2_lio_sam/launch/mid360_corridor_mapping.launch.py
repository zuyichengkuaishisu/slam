import os
from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription
from launch.conditions import IfCondition
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    go2_share = get_package_share_directory('go2_lio_sam')

    params_file = os.path.join(go2_share, 'config', 'params_mid360_corridor.yaml')
    urdf_path = os.path.join(go2_share, 'config', 'robot_mid360.urdf')
    rviz_config = os.path.join(go2_share, 'config', 'lio_sam_mapping.rviz')

    with open(urdf_path, 'r') as f:
        robot_description = f.read()

    use_rviz = LaunchConfiguration('rviz')
    start_livox = LaunchConfiguration('start_livox')
    use_livox_bridge = LaunchConfiguration('use_livox_bridge')
    use_sim_time = LaunchConfiguration('use_sim_time')

    slam_params = [params_file, {'use_sim_time': use_sim_time}]

    return LaunchDescription([
        DeclareLaunchArgument('rviz', default_value='false',
                              description='Launch rviz2 (needs DISPLAY; use true on desktop)'),
        DeclareLaunchArgument('start_livox', default_value='true',
                              description='Launch livox driver (set false if using go2_slam launch)'),
        DeclareLaunchArgument('use_livox_bridge', default_value='true',
                              description='Bridge /livox/lidar CustomMsg to PointCloud2 for LIO-SAM'),
        DeclareLaunchArgument('use_sim_time', default_value='false',
                              description='Set true when playing rosbag with --clock'),

        IncludeLaunchDescription(
            PythonLaunchDescriptionSource(
                os.path.join(go2_share, 'launch', 'mid360_livox.launch.py')
            ),
            condition=IfCondition(start_livox),
        ),

        Node(
            package='go2_lio_sam',
            executable='livox_custom_to_pc2',
            name='livox_custom_to_pc2',
            parameters=[{
                'input_topic': '/livox/lidar',
                'output_topic': '/livox/lidar_pc2',
                'output_frame': 'livox_frame',
                'filter_invalid_tags': True,
                'max_line': 4,
                'use_sim_time': use_sim_time,
            }],
            condition=IfCondition(use_livox_bridge),
            output='screen',
        ),

        Node(
            package='tf2_ros',
            executable='static_transform_publisher',
            arguments=['0', '0', '0', '0', '0', '0', 'map', 'odom'],
            output='screen',
        ),
        Node(
            package='robot_state_publisher',
            executable='robot_state_publisher',
            name='robot_state_publisher',
            parameters=[{'robot_description': robot_description, 'use_sim_time': use_sim_time}],
            output='screen',
        ),
        Node(
            package='lio_sam',
            executable='lio_sam_imuPreintegration',
            name='lio_sam_imuPreintegration',
            parameters=slam_params,
            output='screen',
        ),
        Node(
            package='lio_sam',
            executable='lio_sam_imageProjection',
            name='lio_sam_imageProjection',
            parameters=slam_params,
            output='screen',
        ),
        Node(
            package='lio_sam',
            executable='lio_sam_featureExtraction',
            name='lio_sam_featureExtraction',
            parameters=slam_params,
            output='screen',
        ),
        Node(
            package='lio_sam',
            executable='lio_sam_mapOptimization',
            name='lio_sam_mapOptimization',
            parameters=slam_params,
            output='screen',
        ),
        Node(
            condition=IfCondition(use_rviz),
            package='rviz2',
            executable='rviz2',
            name='rviz2',
            arguments=['-d', rviz_config],
            parameters=[{'use_sim_time': use_sim_time}],
            output='screen',
        ),
    ])
