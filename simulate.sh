#!/bin/bash -f
cp tb/comp_params.v comp_params.bak
cp gen_comp_params.v tb/comp_params.v
DIR=$(pwd)
IN_NAME=$1
GOLDEN=$2
BUBBLES=$3

BUBBLE_ARG=""
if [[ "$3" = "BUBBLES" ]]; then
	BUBBLE_ARG="-testplusarg BUBBLES"
fi

rm out_0.bin
rm out_1.bin

cd project/project.sim/sim_1/behav
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
./compile.sh
./elaborate.sh
ExecStep $xv_path/bin/xsim top_tb_behav -key {Behavioral:sim_1:Functional:top_tb} -tclbatch ../../../../tcl/simulate.tcl -testplusarg IN_FILENAME=$DIR/$IN_NAME -testplusarg OUT_DIR=$DIR $BUBBLE_ARG
cd $DIR
mv comp_params.bak tb/comp_params.v
cmp out_0.bin $GOLDEN
cmp out_1.bin $GOLDEN
