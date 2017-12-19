### Win32 控制台 Wiki 管理工具  

* ### 环境依赖  
  perl for windows  
  Win32::Console  
  File::Temp  
  YAML

* ### 2017-12-17
  标题/键 采用GBK形式直接存储，笔记内容采用UTF8形式编辑和存储。
  在终端显示时转GBK

* 菜单结构体
  存储不同层次下的菜单列表信息
  ```perl
  @info = (
      {                  # ---> level 0
          "key1" => 
          {   x    =>value, 
              light=>bool, 
              str  =>keyname, 
              ref  =>self
              y    =>value,
              length => strlen
          },
          "key2" => {},
          "key3" => {},
      },
      {                  # ---> level 1
          "key1/name1" => {},
          "key1/name2" => {},
          ...
      },
  )
  ```



