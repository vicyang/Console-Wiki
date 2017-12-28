use warnings;
use utf8;
use feature     qw/state/;
use Time::HiRes qw/sleep time/;
use Encode      qw/from_to encode decode/;
use Storable    qw/freeze thaw/;
use Crypt::CBC;
use Cwd;
use File::Slurp;
use File::Temp  qw/tempfile/;
use Win32::Console;
use FindBin;
use lib $FindBin::Bin;         #添加脚本路径到lib搜索目录
use lib $FindBin::Bin ."/lib";

use IO::Handle;
STDOUT->autoflush(1);

INIT
{
    require console;
    require command;
    require menu;
    require store;
    
    our $env_ref;
    our $env_ref_name;
    our ($MAX_COL, $MAX_LINE) = (120, 30);
    our $MATRIX = $MAX_COL * $MAX_LINE;
    our $BOM = "\xef\xbb\xbf";

    our $IN = Win32::Console->new(STD_INPUT_HANDLE);
    our $OUT= Win32::Console->new(STD_OUTPUT_HANDLE);
    our $IN_DEFAULT = $IN->Mode();

    system("mode con cols=$MAX_COL");
    $OUT->Window(1, 0, 0, 119, 29);
    
    #光标高度，若在循环中反复指定高度，则光标会闪烁频繁
    $OUT->Cursor(1, 1, 99, 1);  

    #默认文件
    our $File = "notes_plain.db";
}

if ( defined $ARGV[0] and (-e $ARGV[0]) )
{
    $File = $ARGV[0];
    $File =~s/\\/\//g;
}

$OUT->Title("Wiki - $File");

$IN->Mode(ENABLE_MOUSE_INPUT);

my %hash;
my @info;

load_data( \%hash, $File );
$OUT->FillAttr($FG_WHITE | $BG_CYAN, $MATRIX, 0, 0);  #背景填充，0, 0为起点

GO_BACK:
#首列
our @indent = (1);
@info = ();
$indent[1] = expand(\%hash, \%{$info[0]}, "", $indent[0]);  #first key=""

our @prev=();
our $INDENT = 2;   #统一缩进量

my ($mx, $my);
my $BackupRect;
my $max_level=6;
my $cur_level=0;

GO_CONTINUE: 
while (1) 
{
    sleep 0.02;
    my @arr = $IN->Input();
    my $inside;
    next if ( $#arr < 0 );

    if ( $arr[0] == 2 ) #arr[0] -> key or mouse, [1] -> mouse x, [2] -> mouse y
    {
        ($mx, $my) = ($arr[1], $arr[2]);
        $inside = 0;

        for my $i (0 .. $max_level)     # 0,1,2代表列表的层次
        {
            my $j = $i+1;
            for my $path (keys %{$info[$i]})   #这个$path是fullpath的
            {
                #如果位于某个条目并且状态并非高亮 -> 切换到高亮并显示下一级条目
                if ( inItem( $info[$i]{$path}, @arr[1,2]  ) )
                {
                    $inside++;
                }

                if (  inItem( $info[$i]{$path}, @arr[1,2] ) 
                                and 
                        $info[$i]{$path}{light}==0  )
                {
                    #加一句cursor 0,0 似乎能阻止条目高亮出现缺口
                    $OUT->Cursor(0,0);
                    HighLightItem( $info[$i]{$path} );

                    #清理次级高亮条目 (首层的光标改变时), 放在expand之前执行，
                    if (defined $prev[$j]) 
                    {
                        ClearLight( $info[$j]{$prev[$j]} );
                        undef $prev[$j];
                        for my $clear ($j..$max_level) 
                        {
                            undef %{$info[$clear]};
                        }
                    }

                    $indent[$j+1] = 
                        expand(
                            $info[$i]{$path}{'self'},   #当前对象
                            $info[$j],                  #设置下一级菜单
                            $path,                      #完整path
                            $indent[$j]+$INDENT         #缩进量
                        );

                    #移除当前条目上一次的光标
                    ClearLight( $info[$i]{$prev[$i]} ) if defined $prev[$i];
                    $prev[$i] = $path;
                }

                #显示信息摘要 
                if ( inDetail($info[$i]{$path}, @arr[1,2]) )
                {
                    show_info(
                        $info[$i]{$path},
                        $indent[$j]+$INDENT,
                        \$BackupRect
                    );
                }

                #单击鼠标左键时显示所有详细信息
                if ( inItem($info[$i]{$path}, @arr[1,2]) and $arr[3]==1 )
                {
                    show_detail( $info[$i]{$path}{'self'} );
                }

                #右键菜单
                if ( inItem($info[$i]{$path}, @arr[1,2]) and $arr[3]==2 )
                {
                    context_menu(
                        #缩进        坐标     当前级$info 绝对路径
                        $indent[$j], $arr[2], $info[$i], $path, $i
                    );
                }
            }
        }

        $OUT->Cursor($mx, $my);
    } 
    elsif ($arr[0]==1 and $arr[1]==1 and $arr[5]==27)
    {
        save(\%hash, $File);
        $OUT->Cls();
        exit;
    }
    elsif ($arr[0]==1 and $arr[1]==1 and lc(chr($arr[5])) eq 's') 
    {
        save(\%hash, $File);
        wrong("", "save!");
    }
    elsif ($arr[0]==1 and $arr[1]==1 and lc(chr($arr[5])) eq 'q') 
    {
        $OUT->Cls();
        $OUT->Write("Exit without saving\n");
        exit;
    }
    elsif ($arr[0]==1 and $arr[1]==1 and $arr[3]==116) #F5 刷新界面从头开始
    {
        $IN->Mode(ENABLE_MOUSE_INPUT);
        goto GO_BACK;
    }
}

sub expand
{
    my ($ref, $info, $parent, $indent) = @_;
    my ($cx, $cy) = ( $indent, 1 );
    ClearRect($cx, $MAX_COL, 1, $MAX_LINE);
    my $mark;
    my $max=0;
    my $len=0;
    my @fold;
    my @file;

    %$info=();
    my $tkid;
    for my $kid (sort keys %$ref)
    {
        next if ($kid eq 'note');     #跳过笔记标记
        $tkid = $kid;
        $mark = $parent .":". $kid;
        $tkid =~s/^\d_//;             #去掉编号信息
        
        if ( (keys %{$ref->{$kid}} ) > 1 ) 
        {
            $tkid = "/". $tkid;
            push @fold, $mark;
        } else {
            push @file, $mark;
        }

        $tkid = " $tkid ";
        $len = length($tkid);
        $max = $len if ( $len > $max );

        $$info{$mark} = {       # key name使用完整路径
            "x"     => $cx,     # 由于@fold和@file分开列出，所以$cy在后面排列时设置
            "light" => 0,       # 高亮状态
            "str"   => $tkid,   # 用于显示的keyname
            "self"  => $ref->{$kid},   # 该key的引用
            "parent"=> $ref,
        };
    }

    for ( @fold, @file ) 
    {    
        $$info{$_}{"y"} = $cy++;
        $$info{$_}{"length"} = $max;

        $OUT->Cursor($$info{$_}{x}, $$info{$_}{y});
        $OUT->Write($$info{$_}{str}); 
        $OUT->FillAttr(
            $FG_WHITE|$BG_CYAN, 
            $$info{$_}{length}, 
            $$info{$_}{x}, 
            $$info{$_}{y}
        );
    }
    return $max+$indent;
}

sub show_detail 
{
    our $IN;
    my $item_ref = shift;
    my @arr;
    my $BACKUP;
    my $IN_MODE_RECORD;
    my $tmpstr;
    $BACKUP = $OUT->ReadRect(1, 1, $MAX_COL, $MAX_LINE);
    $IN_MODE_RECORD = $IN->Mode();

	SHOW:
    $OUT->Cls();
    $OUT->Cursor(0,1);    #从第一行开始写信息

    $tmpstr = $item_ref->{'note'};
    from_to($tmpstr, 'utf8', 'gbk');
    print $tmpstr;

    $IN->Mode($IN_DEFAULT);
    my $inp;
    while (1) 
    {
        sleep 0.02;
        @arr = $IN->Input();
        next if $#arr < 0;
        if ($arr[0]==1 and $arr[5]==27) 
        {
            $IN->Mode($IN_MODE_RECORD);
            last;
        }
        elsif ($arr[0]==1 and $arr[3]==17) #control
        {
            $inp = inputBar( $item_ref );
            $IN->Mode($IN_MODE_RECORD);
            $OUT->Cursor(0, 0);
            goto SHOW;
        }
    }
    $OUT->Cls();
    $OUT->FillAttr($FG_WHITE | $BG_CYAN, $MATRIX, 0, 0);
    $OUT->WriteRect($BACKUP, 1, 1, $MAX_COL, $MAX_LINE);
}

sub show_info 
{
    my ($info, $indent, $PREV_RECT) = @_;
    my ($mx, $my);
    my @arr=();
    my $inity = 8;
    my ($cx, $cy)=($indent, $inity);
    my $col_area = $MAX_COL - $indent - 1;  #比最大边界少1

    my $line_area = $MAX_LINE - $cy;
    $PREV_RECT = $OUT->ReadRect($cx, $cy, $MAX_COL, $MAX_LINE);
    ClearRect($cx, $MAX_COL, $cy, $MAX_LINE);

    my $i = 0;
    my $tmpstr;
    my $nn;
    my @detail;
    my @notes;

    if ( exists $info->{'self'}{'note'} ) 
    { 
        $tmpstr = $info->{'self'}{'note'};
        from_to($tmpstr, 'utf8', 'gbk');
        @notes = split /\r?\n/, $tmpstr;
    }
    else { @notes = () }

    for ( @notes ) 
    {
        $i++;
        $nn = sprintf("%02d ", $i);
        $tmpstr = $_;
        $tmpstr =~s/\t/    /g;
        $tmpstr = substr($nn . $tmpstr, 0, $col_area);

        $OUT->Cursor($cx, $cy);
        $OUT->Write( $tmpstr );
        $OUT->FillAttr($FG_YELLOW|$BG_CYAN, $col_area, $cx, $cy++);
        last if ($cy >= ($MAX_LINE-1));
    }
    
    if ( $i == 0 )
    {
        $OUT->Cursor($cx, $cy);
        $OUT->Write("There is nothing");
        $OUT->FillAttr($FG_YELLOW|$BG_CYAN, $col_area, $cx, $cy);
    }

    #循环：当鼠标移开时恢复原来的信息
    my ($x, $y, $len) = @{$info}{'x', 'y', 'length'};

    while (1) 
    {
        sleep 0.03;
        @arr=$IN->Input();
        next if $#arr < 0;
        if ($arr[0] == 2)        #0 => key/mouse, 1 => x, 2 => y
        {   
            ($mx, $my) = ($arr[1], $arr[2]);
            $OUT->Cursor($mx, $my);
            if (not inDetail( $info, $mx, $my) )
            {
                $OUT->WriteRect($PREV_RECT, $cx, $inity, $MAX_COL, $MAX_LINE);
                last;
            }
        }
    }
}


OTHER_FUNCTION: 
{
    sub get_date 
    {
        my (
            $sec, $min, $hour,$mday, $mon, $year,$wday, $yday, $isdst
        ) = localtime( time() );
        return sprintf("%d-%02d-%02d", $year+1900, $mon+1, $mday);
    }
}
