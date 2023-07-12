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
# arctan
create_ip -name cordic -vendor xilinx.com -library ip -version 6.0 -module_name cordic_arctan
set_property -dict [list CONFIG.Functional_Selection {Arc_Tan} CONFIG.Data_Format {SignedFraction}] [get_ips cordic_arctan]
set_property -dict [list CONFIG.ARESETN {true}] [get_ips cordic_arctan]
set_property -dict [list CONFIG.cartesian_has_tlast {true} CONFIG.out_tlast_behv {Pass_Cartesian_TLAST}] [get_ips cordic_arctan]
set_property -dict [list CONFIG.Phase_Format {Scaled_Radians}] [get_ips cordic_arctan]
set_property -dict [list CONFIG.Input_Width {17} CONFIG.Output_Width {17}] [get_ips cordic_arctan]
# # sqrt
# create_ip -name cordic -vendor xilinx.com -library ip -version 6.0 -module_name cordic_sqrt
# set_property -dict [list CONFIG.ARESETN {true}] [get_ips cordic_sqrt]
# set_property -dict [list CONFIG.Functional_Selection {Square_Root} CONFIG.Data_Format {UnsignedInteger} CONFIG.Input_Width {21} CONFIG.Output_Width {11} CONFIG.Coarse_Rotation {false}] [get_ips cordic_sqrt]

