vsim +access+r +UVM_TESTNAME=riscv_random_test -sv_seed 100;
run -all;
acdb save;
acdb report -db  fcover.acdb -txt -o cov.txt -verbose  
exec cat cov.txt;
exit
