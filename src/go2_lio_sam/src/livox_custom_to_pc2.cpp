#include <cstring>
#include <memory>
#include <string>

#include <rclcpp/rclcpp.hpp>
#include <sensor_msgs/msg/point_cloud2.hpp>
#include <sensor_msgs/msg/point_field.hpp>
#include <livox_ros_driver2/msg/custom_msg.hpp>

#pragma pack(push, 1)
struct LivoxPointXyzrtlt
{
  float x;
  float y;
  float z;
  float reflectivity;
  uint8_t tag;
  uint8_t line;
  double timestamp;
};
#pragma pack(pop)
static_assert(sizeof(LivoxPointXyzrtlt) == 26, "Livox point layout mismatch");

class LivoxCustomToPc2 : public rclcpp::Node
{
public:
  LivoxCustomToPc2() : Node("livox_custom_to_pc2")
  {
    declare_parameter<std::string>("input_topic", "/livox/lidar");
    declare_parameter<std::string>("output_topic", "/livox/lidar_pc2");
    declare_parameter<std::string>("output_frame", "");
    declare_parameter<bool>("filter_invalid_tags", true);
    declare_parameter<int>("max_line", 4);

    get_parameter("input_topic", input_topic_);
    get_parameter("output_topic", output_topic_);
    get_parameter("output_frame", output_frame_);
    get_parameter("filter_invalid_tags", filter_invalid_tags_);
    get_parameter("max_line", max_line_);

    // 发布用 Reliable：RViz 默认可收；LIO-SAM 的 Best Effort 订阅也可收
    auto pub_qos = rclcpp::QoS(rclcpp::KeepLast(5)).reliable();
    // 订阅 Livox/bag 输入保持 SensorDataQoS（Best Effort）
    auto sub_qos = rclcpp::SensorDataQoS();

    pub_ = create_publisher<sensor_msgs::msg::PointCloud2>(output_topic_, pub_qos);
    sub_ = create_subscription<livox_ros_driver2::msg::CustomMsg>(
      input_topic_, sub_qos,
      std::bind(&LivoxCustomToPc2::customMsgCallback, this, std::placeholders::_1));

    RCLCPP_INFO(get_logger(),
      "Livox bridge: %s (CustomMsg) -> %s (PointCloud2/PointXYZRTLT)",
      input_topic_.c_str(), output_topic_.c_str());
  }

private:
  static bool isValidLivoxTag(uint8_t tag)
  {
    return (tag & 0x30) == 0x10 || (tag & 0x30) == 0x00;
  }

  static void initPointCloud2Header(sensor_msgs::msg::PointCloud2 & cloud)
  {
    cloud.fields.resize(7);
    cloud.fields[0].name = "x";
    cloud.fields[0].offset = 0;
    cloud.fields[0].datatype = sensor_msgs::msg::PointField::FLOAT32;
    cloud.fields[0].count = 1;
    cloud.fields[1].name = "y";
    cloud.fields[1].offset = 4;
    cloud.fields[1].datatype = sensor_msgs::msg::PointField::FLOAT32;
    cloud.fields[1].count = 1;
    cloud.fields[2].name = "z";
    cloud.fields[2].offset = 8;
    cloud.fields[2].datatype = sensor_msgs::msg::PointField::FLOAT32;
    cloud.fields[2].count = 1;
    cloud.fields[3].name = "reflectivity";
    cloud.fields[3].offset = 12;
    cloud.fields[3].datatype = sensor_msgs::msg::PointField::FLOAT32;
    cloud.fields[3].count = 1;
    cloud.fields[4].name = "tag";
    cloud.fields[4].offset = 16;
    cloud.fields[4].datatype = sensor_msgs::msg::PointField::UINT8;
    cloud.fields[4].count = 1;
    cloud.fields[5].name = "line";
    cloud.fields[5].offset = 17;
    cloud.fields[5].datatype = sensor_msgs::msg::PointField::UINT8;
    cloud.fields[5].count = 1;
    cloud.fields[6].name = "timestamp";
    cloud.fields[6].offset = 18;
    cloud.fields[6].datatype = sensor_msgs::msg::PointField::FLOAT64;
    cloud.fields[6].count = 1;
    cloud.point_step = sizeof(LivoxPointXyzrtlt);
    cloud.is_bigendian = false;
    cloud.is_dense = true;
    cloud.height = 1;
  }

  void customMsgCallback(const livox_ros_driver2::msg::CustomMsg::SharedPtr msg)
  {
    std::vector<LivoxPointXyzrtlt> points;
    points.reserve(msg->points.size());

    for (const auto & src : msg->points) {
      if (filter_invalid_tags_ && !isValidLivoxTag(src.tag)) {
        continue;
      }
      if (src.line >= static_cast<uint8_t>(max_line_)) {
        continue;
      }

      LivoxPointXyzrtlt dst;
      dst.x = src.x;
      dst.y = src.y;
      dst.z = src.z;
      dst.reflectivity = static_cast<float>(src.reflectivity);
      dst.tag = src.tag;
      dst.line = src.line;
      dst.timestamp = static_cast<double>(msg->timebase + src.offset_time);
      points.push_back(dst);
    }

    if (points.empty()) {
      RCLCPP_WARN_THROTTLE(get_logger(), *get_clock(), 2000,
        "No valid points after filtering in CustomMsg");
      return;
    }

    sensor_msgs::msg::PointCloud2 cloud;
    initPointCloud2Header(cloud);
    cloud.header = msg->header;
    if (!output_frame_.empty()) {
      cloud.header.frame_id = output_frame_;
    }
    cloud.width = static_cast<uint32_t>(points.size());
    cloud.row_step = cloud.width * cloud.point_step;
    cloud.data.resize(points.size() * sizeof(LivoxPointXyzrtlt));
    std::memcpy(cloud.data.data(), points.data(), cloud.data.size());
    pub_->publish(cloud);
  }

  std::string input_topic_;
  std::string output_topic_;
  std::string output_frame_;
  bool filter_invalid_tags_{true};
  int max_line_{4};

  rclcpp::Subscription<livox_ros_driver2::msg::CustomMsg>::SharedPtr sub_;
  rclcpp::Publisher<sensor_msgs::msg::PointCloud2>::SharedPtr pub_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<LivoxCustomToPc2>());
  rclcpp::shutdown();
  return 0;
}
