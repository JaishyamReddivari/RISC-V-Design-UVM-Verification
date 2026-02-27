interface commit_if(input logic clk);

  logic        valid;
  logic [31:0] pc;
  logic [4:0]  rd;
  logic [31:0] data;
  logic [31:0] instr;
  logic [1:0] forward_a;
  logic [1:0] forward_b;
  logic stall_if;
  logic flush_ex;
  logic redirect_valid;
  logic rst_drive;

endinterface
