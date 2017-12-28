2017-12-17
  Perl 32bit Storable 存储的数据，使用 Perl 64bit Storable 加载并 thaw
  显示 
  Pointer size is not compatible at C:/Strawberry/perl/lib/Storable.pm line 426, at D:\Sync\notes\load.pl line 5.

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

