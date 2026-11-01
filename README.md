# JoyoseConfig-Get

从服务器拉joyose的teg_config

## 使用说明

双击运行即可，拉到数据后会打成压缩包，如果包内没有[booster_config].json说明小米没推，正常有这俩文件：  
```text
[booster_config].json
[common_config].json
```
## 默认配置
$Device = "songyuan"  
$MiuiRegion = "CN"  
$Locale = "zh_CN"  
$Incremental = "4.0.5.0.AUTO"  
$MiuiVersionName = "V816"  
$BuildType = "stable"  
$AndroidRelease = "16"  

拉取其他设备配置一般只需要修改设备代号 

## 注
设备ROM的一般自带配置文件，位置在: /odm/etc/default_cloud.json  
default_cloud.json需自行解密或用scene等工具查看  
default_cloud与teg_config谁的日期高谁就优先  
