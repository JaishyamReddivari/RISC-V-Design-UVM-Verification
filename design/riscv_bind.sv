bind riscv_core riscv_assertions u_core_assertions(
  .clk 			     (clk),
  .rst_n 		     (rst_n),
  
  .if_id_pc 	     (if_id.pc),
  
  .stall_if		     (stall_if),
  .stall_id		     (stall_id),
  .flush_ex 	     (flush_ex),
  
  .redirect_valid    (redirect_valid),
  .redirect_pc       (redirect_pc),
  
  .mem_read          (ex_mem.ctrl.mem_read),
  .mem_write         (ex_mem.ctrl.mem_write),
  
  .reg_write	     (mem_wb.ctrl.reg_write),
  .mem_to_reg 	     (mem_wb.ctrl.mem_to_reg),
  
  .mem_data		     (mem_wb.mem_data),
  .alu_result	     (mem_wb.alu_result),
  
  .commit_valid	     (commit.valid),
  .commit_data	     (commit.data),
  .commit_pc 	     (commit.pc),
  
  .id_rs1 		     (if_id.instr[19:15]),
  .id_rs2 		     (if_id.instr[24:20]),
  
  .id_ex_rs1 	     (id_ex.rs1),
  .id_ex_rs2 	     (id_ex.rs2),
  
  .hazard_ex_rd 	 (id_ex.rd),
  .hazard_ex_mem_read(id_ex.ctrl.mem_read),
  
  .fwd_ex_rd		 (ex_mem.rd),
  .fwd_ex_reg_write  (ex_mem.ctrl.reg_write),
  .fwd_mem_rd 		 (mem_wb.rd),
  .fwd_mem_reg_write (mem_wb.ctrl.reg_write),
  
  .forward_a 	     (u_ex.forward_a),
  .forward_b 	     (u_ex.forward_b),
  
  .ex_mem_reg_write  (ex_mem.ctrl.reg_write),
  .ex_mem_mem_read   (ex_mem.ctrl.mem_read),
  .ex_mem_mem_write  (ex_mem.ctrl.mem_write),
  .ex_mem_alu_result (ex_mem.alu_result),
  
  .id_ex_reg_write   (id_ex.ctrl.reg_write),
  
  .id_ex_mem_read    (id_ex.ctrl.mem_read),
  .id_ex_mem_write   (id_ex.ctrl.mem_write),
  
  .id_ex_opcode      (id_ex.instr[6:0]),
  
  .ex_operand_a      (u_ex.operand_a_debug),
  .ex_operand_b      (u_ex.operand_b_debug),
  
  .core_pc  	     (u_if.pc),
  .commit_opcode     (mem_wb.instr[6:0])
);

bind riscv_core riscv_exec_bind u_exec_bind(
  .clk(clk),
  .eif(riscv_tb.eif)
);
