cmake_minimum_required(VERSION 3.5)
project(go2_lio_sam)

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(sensor_msgs REQUIRED)
find_package(livox_ros_driver2 REQUIRED)

add_executable(livox_custom_to_pc2 src/livox_custom_to_pc2.cpp)
ament_target_dependencies(livox_custom_to_pc2
  rclcpp
  sensor_msgs
  livox_ros_driver2
)

install(TARGETS livox_custom_to_pc2
  DESTINATION lib/${PROJECT_NAME}
)

install(DIRECTORY config launch
  DESTINATION share/${PROJECT_NAME}
)

ament_package()
