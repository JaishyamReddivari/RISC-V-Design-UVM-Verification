module riscv_exec_bind(
  input logic clk,
  exec_if eif
);
  
  import riscv_pkg::*;
  
  assign eif.valid = (id_ex.instr != 32'b0);
  assign eif.instr = id_ex.instr;
  assign eif.pc = id_ex.pc;
  assign eif.forward_a = u_ex.forward_a;
  assign eif.forward_b = u_ex.forward_b;
  assign eif.stall_if = u_hazard.stall_if;
  assign eif.flush_ex = u_hazard.flush_ex;
  assign eif.redirect_valid = u_ex.redirect_valid;
  
endmodule
