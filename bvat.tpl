# memory: {{ max_memory }}MB
[mysqld]
    sql_mode = ""
    transaction-isolation = READ-COMMITTED
    innodb_flush_method = O_DIRECT
    innodb_flush_log_at_trx_commit = 2
    query_cache_type = 1
    query_cache_size = {{ query_cache_size }}M
    query_cache_limit = {{ query_cache_limit }}M
    innodb_buffer_pool_size = {{ innodb_buffer_pool_size }}M
    max_connections = {{ max_connections }}
    table_open_cache = {{ table_open_cache }}
    thread_cache_size = {{ thread_cache_size }}
    max_heap_table_size = {{ max_heap_table_size }}M
    tmp_table_size = {{ tmp_table_size }}M
    key_buffer_size = {{ key_buffer_size }}M
    join_buffer_size = {{ join_buffer_size }}M
    sort_buffer_size = {{ sort_buffer_size }}M
    bulk_insert_buffer_size = {{ bulk_insert_buffer_size }}M
    myisam_sort_buffer_size = {{ myisam_sort_buffer_size }}M
