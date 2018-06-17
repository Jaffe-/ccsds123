proc dump_activity {} {
    open_saif activity.saif
    log_saif [get_object -r /top_impl_tb/*]
    run 4000us
    close_saif
}
