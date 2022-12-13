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
    ./cal_rel_phase.sv                  \
    ./rel_phase_4steps.sv               
# Add simulation files
add_files                               \
    -fileset sim_1                      \
    ./tb.sv

# Add ip
create_ip -name cordic -vendor xilinx.com -library ip -version 6.0 -module_name cordic_arctan
set_property -dict [list CONFIG.Functional_Selection {Arc_Tan} CONFIG.Data_Format {SignedFraction}] [get_ips cordic_arctan]
set_property -dict [list CONFIG.ARESETN {true}] [get_ips cordic_arctan]
set_property -dict [list CONFIG.cartesian_has_tlast {true} CONFIG.out_tlast_behv {Pass_Cartesian_TLAST}] [get_ips cordic_arctan]
set_property -dict [list CONFIG.Input_Width {16} CONFIG.Output_Width {16}] [get_ips cordic_arctan]