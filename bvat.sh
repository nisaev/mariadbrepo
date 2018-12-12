#!/bin/bash
#   Generate performance options for configs
#set -x
export LANG=en_EN.UTF-8
export NOLOCALE=yes
export PATH=/sbin:/bin:/usr/sbin:/usr/bin

PERF="/root/bvat.csv"
VARS="query_cache_size;query_cache_limit;table_open_cache;thread_cache_size;max_heap_table_size;tmp_table_size;key_buffer_size;join_buffer_size;sort_buffer_size;bulk_insert_buffer_size;myisam_sort_buffer_size;innodb_buffer_pool_size"
OS_VERSION=$(cat /etc/redhat-release | \
    sed -e "s/CentOS Linux release//;s/CentOS release // " | cut -d'.' -f1)
error(){
    msg="$1"
    echo "{\"changed\":false,\"failed\":true,\"msg\":\"$msg\"}"
    exit 1
}
get_column_number(){
    name="${1}"
    [[ -z $name ]] && error "get_column_number; you must define column name"

    num=$(head -1 $PERF  | \
        awk -F';' ' { for (i = 1; i <= NF; ++i) printf "%d:%s\n", i, $i; exit  }' | \
        grep ":$name$" | awk -F':' '{print $1}')
    [[ -z $num ]] && error "get_column_number; not found column number for $name"
    return $num
}

get_os_type(){
    # is OpenVZ installation
    IS_OPENVZ=$( [[ -f /proc/user_beancounters  ]] && echo 1 || echo 0  )

    # Hardware type
    HW_TYPE=general
    [[ $IS_OPENVZ -gt 0  ]] && HW_TYPE=openvz

    # x86_64 or i386
    IS_X86_64=$(uname -a | grep -wc 'x86_64')
}

# get available memory on board
get_available_memory(){
    [[ -z $IS_X86_64 ]] && get_os_type

    AVAILABLE_MEMORY=$(free | grep Mem | awk '{print $2}')
    if [[ $IS_OPENVZ -gt 0 ]]; then
        if [[ -z $AVAILABLE_MEMORY ]]; then
            mem4kblock=`cat /proc/user_beancounters | \
                grep vmguarpages|awk '{print $4}'`
            mem4kblock2=`cat /proc/user_beancounters | \
                grep privvmpages|awk '{print $4}'`
            if [[ ${mem4kblock2} -gt ${mem4kblock} ]]; then
                AVAILABLE_MEMORY=$(echo "${mem4kblock} * 4"|bc)
            else
                AVAILABLE_MEMORY=$(echo "${mem4kblock2} * 4"|bc)
            fi
        fi
    fi

    AVAILABLE_MEMORY_MB=$(( $AVAILABLE_MEMORY / 1024 ))

    [[ ( $IS_X86_64 -eq 0 ) && ( $AVAILABLE_MEMORY_MB -gt 4096 ) ]] && \
        AVAILABLE_MEMORY_MB=4096
}

get_memory_limits(){
    get_column_number Memory
    memory_column=$?
    
    MEMORY_LIMITS=$(cat $PERF | grep ";$HW_TYPE;" | \
        awk -F';' -v col=$memory_column '{print $col}')
    MIN_MEMORY_MB=0

    MAX_MB=
    for max_mb in $MEMORY_LIMITS; do
        if [[ ( $AVAILABLE_MEMORY_MB -gt $MIN_MEMORY_MB ) && \
             ( $AVAILABLE_MEMORY_MB -le $max_mb ) && ( -z $MAX_MB ) ]]; then
            MAX_MB=$max_mb
        fi
        MIN_MEMORY_MB=$max_mb
    done
    
    # maximum
    [[ $AVAILABLE_MEMORY_MB -gt $max_mb ]] && \
        MAX_MB=$max_mb

    # minimum
    [[ -z $MAX_MB ]] && MAX_MB=512
}

ddopcache(){
        opcache_template=/root/opcache.tpl
        opcache_memory_mb=$(( $AVAILABLE_MEMORY_MB/8 ))
        [[ -z $opcache_memory_mb ]] && opcache_memory_mb=64
        [[ $opcache_memory_mb -lt 64 ]] && opcache_memory_mb=64
        [[ $opcache_memory_mb -gt 2048 ]] && opcache_memory_mb=2048
         opcache_memory_strings=$(( $opcache_memory_mb/4 ))
         opcache_config=/etc/php.d/10-opcache.ini
        [[ "$PHP_VERSION" == "5.4" ]] && opcache_config=/etc/php.d/opcache.ini
         # delete old config file; if there is one
        [[ ( "$PHP_VERSION" != "5.4" ) && \
            ( -f /etc/php.d/opcache.ini ) ]] && \
            rm -f /etc/php.d/opcache.ini
         # update opcache config
        if [[ -f $opcache_template ]]; then
            cat $opcache_template | \
                sed -e "s:__MEMORY__:$opcache_memory_mb:;s:__MEMORYSTR__:$opcache_memory_strings:;" \
                > $opcache_config 2>/dev/null && \
	echo "oke"
	fi    
}


update_config(){
    orig=${1}
    new=${2}

    # test md5 summ
    orig_md5_summ=0
    temp_md5_summ=$(md5sum $new | awk '{print $1}')
    if [[ -f $orig ]]; then
        orig_md5_summ=$(md5sum $orig | awk '{print $1}')
    fi

    if [[ $temp_md5_summ != "$orig_md5_summ" ]]; then
        mv -f $new $orig
        echo "{\"changed\":true,\"msg\":\"Update config $orig\"}"
    else
        rm -f $new
        echo "{\"changed\":false,\"msg\":\"Config $orig is ok\"}"
    fi



}

update_configs_mysql(){

    MYSQL_CONFIG=/etc/my.cnf.d/bvat.cnf
	echo "oke"
    # update mysql config
    MYSQL_CONFIG_TMP=$MYSQL_CONFIG.tmp
    MYSQL_CONFIG_TEMPLATE=/root/bvat.tpl
    cp -f $MYSQL_CONFIG_TEMPLATE $MYSQL_CONFIG_TMP
    for v in $(echo $VARS | sed -e "s/;/ /g"); do
        get_column_number $v
        p=$?

        s=$(cat $PERF | grep ";$MAX_MB;$HW_TYPE;" | \
            awk -F';' -v col=$p '{print $col}')

        sed -i "s/{{\s*$v\s*}}/$s/" $MYSQL_CONFIG_TMP
    done

    # max_connection
    get_column_number "PHP_threads"
    php_threads_col=$?

    php_threads=$(cat $PERF | grep ";$MAX_MB;$HW_TYPE;" | \
        awk -F';' -v col=$php_threads_col '{print $col}')

    max_connections=$(( $php_threads + 25 ))
    start_servers=$php_threads

    sed -i "s/{{\s*max_connections\s*}}/$max_connections/" $MYSQL_CONFIG_TMP
    sed -i "s/{{\s*max_memory\s*}}/$MAX_MB/" $MYSQL_CONFIG_TMP
   

    update_config "$MYSQL_CONFIG" "$MYSQL_CONFIG_TMP"
}

opt=$1
if [[ ( -n $opt ) && ( -f $opt ) ]]; then
    source $opt
else
    state="$opt"
fi

[[ ! -f $PERF ]] && \
    error "Not found config file=$PERF"

# get info about OS
get_os_type

# get installed memory size
get_available_memory

# 
get_memory_limits
update_configs_mysql
ddopcache
