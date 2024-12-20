#!/bin/bash
# 当前目录
SOROY_DIR=$(dirname "$0")
SOROY_DIR=$(realpath "$SOROY_DIR")
# 加载颜色
source $SOROY_DIR/colors.sh
# DNMP目录
DNMP_DIR=$(realpath "$SOROY_DIR/..")
# 加载.env
source $DNMP_DIR/.env
# 默认虚拟主机 配置文件目录
VHOSTS_CONF_DIR=$DNMP_DIR/services/nginx/conf.d
# 默认虚拟主机 站点目录
VHOSTS_DIR=$DNMP_DIR/www
# SSL目录
SSL_DIR=$DNMP_DIR/services/nginx/ssl
# 输入的域名
INPUT_DOMAIN_NAME=""
# 需要操作的站点虚拟主机名
SITE_HOSTNAME=""

# 验证域名
function input_domain {
    # 接收输入域名
    while true; do
        # 域名
        local domain_names
        # 域名是否存在
        local domain_exists=0
        # 请输入域名
        echo -ne "$BC请输入域名(eg:demo.com):$ED "
        # 接收输入域名
        read -r INPUT_DOMAIN_NAME
        # 将域名转换为小写
        INPUT_DOMAIN_NAME=$(echo $INPUT_DOMAIN_NAME | tr 'A-Z' 'a-z')
        # 验证域名是否符合规范
        INPUT_DOMAIN_NAME=$(echo $INPUT_DOMAIN_NAME | awk '/^[a-z0-9][-a-z0-9]{0,62}(\.[a-z0-9][-a-z0-9]{0,62})+$/{print $0}')
        # 验证域名是否符合规范
        if [[ ! "$INPUT_DOMAIN_NAME" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])*(\.[a-z0-9]([-a-z0-9]*[a-z0-9])*)+$ ]]; then
            echoYC "域名有误,请重新输入!!!"
            continue
        else
            # 从配置文件中提取所有的域名并检查是否存在
            domain_names=$(find "$VHOSTS_CONF_DIR" -type f -name "*.conf" -exec grep -oP 'server_name\s+\K[^\s;]+' {} \; | tr '\n' ' ')
            # 遍历域名
            for item in $domain_names; do
                # 检查域名是否存在
                if [ "$INPUT_DOMAIN_NAME" = "$item" ]; then
                    echoCC '域名已存在.'
                    # 域名已存在
                    domain_exists=1
                    break
                fi
            done
            # 如果域名已存在,则继续输入
            if [ $domain_exists -eq 1 ]; then
                continue
            fi
        fi
        break
    done
}

# 创建站点
function create_site {
    # 请输入域名
    input_domain
    # 判断站点目录是否存在
    if [ ! -d "$VHOSTS_DIR/$INPUT_DOMAIN_NAME" ]; then
        # 自动创建站点目录
        mkdir -p "$VHOSTS_DIR/$INPUT_DOMAIN_NAME"
    fi
    # 自动创建站点配置文件
    cp -rf $DNMP_DIR/soroy/site.conf $VHOSTS_CONF_DIR/$INPUT_DOMAIN_NAME.conf
    # 替换域名
    sed -i "s/default_replace_8888/$INPUT_DOMAIN_NAME/" $VHOSTS_CONF_DIR/$INPUT_DOMAIN_NAME.conf
    # 判断站点目录是否存在
    if [ ! -d "$VHOSTS_DIR/$INPUT_DOMAIN_NAME" ]; then
        # 创建站点目录
        mkdir -p $VHOSTS_DIR/$INPUT_DOMAIN_NAME
    fi
    # 创建站点证书目录
    mkdir -p $SSL_DIR/$INPUT_DOMAIN_NAME
    # 先生成密钥文件
    openssl genrsa -out $SSL_DIR/$INPUT_DOMAIN_NAME/key.pem 2048
    # 使用密钥文件生成自签名证书
    openssl req -new -x509 -key $SSL_DIR/$INPUT_DOMAIN_NAME/key.pem -out $SSL_DIR/$INPUT_DOMAIN_NAME/cert.pem -days 365 -subj "/C=CN/ST=Beijing/L=Beijing/O=Soroy/OU=Soroy/CN=$INPUT_DOMAIN_NAME"
    # 下载wordpress
    wget -O $VHOSTS_DIR/$INPUT_DOMAIN_NAME/wordpress.zip https://wordpress.org/latest.zip
    # 解压wordpress 到站点目录 不输出
    unzip -o $VHOSTS_DIR/$INPUT_DOMAIN_NAME/wordpress.zip -d $VHOSTS_DIR/$INPUT_DOMAIN_NAME > /dev/null 2>&1
    # 删除wordpress.zip
    rm -rf $VHOSTS_DIR/$INPUT_DOMAIN_NAME/wordpress.zip
    # 修改文件权限 - 使用容器内的路径
    docker exec php82 chown -R www-data:www-data /www/$INPUT_DOMAIN_NAME
    # 数据库名 替换.为_ -为_
    DATABASE_NAME=$(echo $INPUT_DOMAIN_NAME | tr '.' '_' | tr '-' '_')
    # 创建站点数据库
    docker exec mysql mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE $DATABASE_NAME;"
    # 重新加载nginx配置
    docker exec nginx nginx -s reload
    # 输出成功
    echoGC "站点创建成功,请访问: https://$INPUT_DOMAIN_NAME"
    # 输出数据库名
    echoGC "数据库名: $DATABASE_NAME"
    # 输出数据库用户名
    echoGC "数据库用户名: root"
    # 输出数据库密码
    echoGC "数据库密码: $MYSQL_ROOT_PASSWORD"
}

# 获取站点虚拟主机名
function site_hostname_get {
    # 声明局部数组
    local -a sites
    # 使用通配符直接读取到数组
    sites=("$VHOSTS_DIR"/*)
    # 如果目录为空，则退出
    if [ ${#sites[@]} -eq 0 ]; then
        echo "没有找到任何站点"
        return 1
    fi
    # 去除路径前缀，只保留站点名
    for i in "${!sites[@]}"; do
        sites[$i]=$(basename "${sites[$i]}")
    done
    # 显示站点列表
    local i=1
    for site in "${sites[@]}"; do
        echo -e "${YC}${i}${ED}.${LG}${site}${ED}"
        ((i++))
    done
    # 读取用户输入并验证
    while true; do
        read -p "请输入站点序号(1-${#sites[@]}): " site_index
        # 验证输入是否为数字
        if ! [[ "$site_index" =~ ^[0-9]+$ ]]; then
            echo "请输入有效的数字"
            continue
        fi
        # 验证范围
        if [ "$site_index" -lt 1 ] || [ "$site_index" -gt ${#sites[@]} ]; then
            echo "请输入 1 到 ${#sites[@]} 之间的数字"
            continue
        fi
        break
    done
    # 获取选择的站点名（数组索引从0开始，所以要减1）
    SITE_HOSTNAME="${sites[$((site_index-1))]}"
    echo "$SITE_HOSTNAME"
    return 0
}

# 追加域名
function site_append_domain {
    # 获取站点虚拟主机名
    site_hostname_get
    # 请输入域名
    input_domain
    # 虚拟主机配置文件
    local site_conf_file=$VHOSTS_CONF_DIR/$SITE_HOSTNAME.conf
    # 在配置文件中追加域名 先找到 server_name 然后追加域名
    sed -i '/server_name/ s/;/ '"$INPUT_DOMAIN_NAME"';/' $site_conf_file
    # 重新加载nginx配置
    docker exec nginx nginx -s reload
    # 输出成功
    echoGC "域名追加成功,请访问: https://$INPUT_DOMAIN_NAME"
}

# 安装SSL证书
function site_install_ssl {
    # 判断 acme.sh 是否安装
    if ! command -v acme.sh &> /dev/null; then
        # 安装 acme.sh
        curl https://get.acme.sh | sh
    fi
    # 获取站点虚拟主机名
    # 获取站点虚拟主机名
    site_hostname_get

    # 安装SSL证书
    docker exec nginx nginx -s reload
}

# 站点命令
function site_cmd {
    # 循环
    while true; do
        # 显示菜单
        echo -e "${YC}1${ED}.${LG}创建站点${ED}"
        echo -e "${YC}2${ED}.${LG}追加域名${ED}"
        echo -e "${YC}3${ED}.${LG}安装SSL证书${ED}"
        echo -e "${YC}e${ED}.${LG}返回${ED}"
        echo -ne "${BC}请选择: ${ED}"
        read -a num2
        case $num2 in 
            1) create_site ;;
            2) site_append_domain ;;
            e) break ;;
            *) echoCC '输入有误.'
        esac
        continue
    done
}

site_cmd