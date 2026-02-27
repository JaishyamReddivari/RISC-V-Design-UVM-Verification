interface exec_if(input logic clk);
  
  logic valid;
  logic [31:0] instr;
  logic [31:0] pc;
  logic [1:0] forward_a;
  logic [1:0] forward_b;
  logic stall_if;
  logic flush_ex;
  logic redirect_valid;

endinterface
