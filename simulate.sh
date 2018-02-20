#!/bin/bash -f
cp tb/comp_params.v comp_params.bak
cp gen_comp_params.v tb/comp_params.v
DIR=$(pwd)
cd project/project.sim/sim_1/behav
./compile.sh
./elaborate.sh
xv_path="/opt/Xilinx/Vivado/2017.2"
ExecStep()
{
"$@"
RETVAL=$?
if [ $RETVAL -ne 0 ]
then
exit $RETVAL
fi
}
ExecStep $xv_path/bin/xsim top_tb_behav -key {Behavioral:sim_1:Functional:top_tb} -tclbatch ../../../../tcl/simulate.tcl -testplusarg IN_FILENAME=$1 -testplusarg OUT_FILENAME=$DIR/$2
cd $DIR
mv comp_params.bak tb/comp_params.v
cmp $2 $3
