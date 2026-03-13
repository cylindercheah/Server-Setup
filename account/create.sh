#!/bin/bash

# 定义用户列表（中文姓名）
USERS="liutianyue"

# 统一密码
PASSWORD="ltysjtu"

# 转换中文名拼音函数（简单实现，可能需要调整）
function name_to_pinyin() {
    case $1 in
        "梁政实") echo "liangzhengshi";;
        "田洁晨") echo "tianjiechen";;
        "龙羿辰") echo "longyichen";;
        "龙雨时") echo "longyushi";;
        "陈奕扬") echo "chenyiyang";;
        "杨智旭") echo "yangzhixu";;
        "yuhanlin") echo "yuhanlin";;
        *) echo "";;
    esac
}

echo "开始批量创建用户..."

for NAME in $USERS; do
    # 获取英文用户名
    USERNAME=$(name_to_pinyin "$NAME")
    
    if [ -z "$USERNAME" ]; then
        echo "错误：无法处理姓名 $NAME"
        continue
    fi
    
    # 检查用户是否已存在
    if id "$USERNAME" &>/dev/null; then
        echo "用户 $USERNAME ($NAME) 已存在，跳过创建"
        continue
    fi
    
    # 创建用户
    echo "正在创建用户: $USERNAME ($NAME)"
    sudo useradd -m -s /bin/zsh -c "$NAME" "$USERNAME"
    
    # 设置密码
    echo "$USERNAME:$PASSWORD" | sudo chpasswd
    
    # 显示创建结果
    echo "已创建用户 $USERNAME ($NAME), shell: /bin/zsh, 密码: $PASSWORD"
done

echo "用户创建完成。以下是已创建用户列表："
echo "----------------------------------"
for NAME in $USERS; do
    USERNAME=$(name_to_pinyin "$NAME")
    if id "$USERNAME" &>/dev/null; then
        echo "用户名: $USERNAME, 姓名: $NAME"
    fi
done
echo "----------------------------------"
echo "所有用户密码均为: $PASSWORD"
echo "所有用户shell均为: /bin/zsh"
