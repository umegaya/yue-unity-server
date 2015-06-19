# yue-unity-server
server infrastructure of yue-unity

# how to run
```
curl https://raw.githubusercontent.com/umegaya/yue/master/yue -o /path/to/your/bin/yue
cd this_repo
yue init com.your.project.name
yue src/main.lua

### if you want to run on ec2, 
### edit .yue/factory as you need (note: $VARIABLE will be replaced corresponding env value), 
### then do below.
yue node create -t amazonec2 machine_name
yue build your_dockerhub_user/your_image_name
yue your_dockerhub_user/your_image_name -H machine_name
```
