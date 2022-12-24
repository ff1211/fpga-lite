#****************************************************************
# Copyright 2022 Tianjin University 305 Lab. All Rights Reserved.
#
# File:
# add_files.tcl
# 
# Description:
# Tcl script to add files to vivado project.
# 
# Revision history:
# Version  Date        Author      Changes      
# 1.0      2022.12.04  ff          Initial version
#****************************************************************

# Project specific configurations.
set DATA_WIDTH "16"

# Add source files
add_files                               \
    ../../../shell/common/sync_fifo.sv  \
    ../../../shell/common/tdual_ram.sv  \
    ../../../shell/common/shift_reg.sv  \
    ./cal_disparity.sv                  \
    ./search_core.sv                    \
    ./match_core.sv                     \
    ./phase_cache.sv                    \
    ./control.sv                        \
    ./match_phase.sv
# Add simulation files
add_files                               \
    -fileset sim_1                      \
    ./tb.sv

# Add ip
create_ip -name div_gen -vendor xilinx.com -library ip -version 5.1 -module_name div_gen_0
set_property -dict [list                    \
  CONFIG.OutTLASTBehv {Pass_Dividend_TLAST} \
  CONFIG.dividend_and_quotient_width {24}   \
  CONFIG.dividend_has_tlast {true}          \
  CONFIG.divisor_width {16}                 \
  CONFIG.fractional_width {16}              \
  CONFIG.latency {28}                       \
] [get_ips div_gen_0]
set_property CONFIG.dividend_has_tuser {true} [get_ips div_gen_0]
set_property -dict [list CONFIG.dividend_tuser_width {17}] [get_ips div_gen_0]