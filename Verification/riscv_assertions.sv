import riscv_pkg::*;
module riscv_assertions(
  
  input logic clk,
  input logic rst_n,
  
  input logic [31:0] if_id_pc,
  
  input logic stall_if,
  input logic stall_id,
  input logic flush_ex,
  
  input logic redirect_valid,
  input logic [31:0] redirect_pc,
  
  input logic reg_write,
  input logic mem_to_reg,
  
  input logic mem_read,
  input logic mem_write,
  
  input logic [31:0] mem_data,
  input logic [31:0] alu_result,
  
  input logic commit_valid,
  input logic [31:0] commit_data,
  
  input logic [4:0] id_rs1,
  input logic [4:0] id_rs2,
  
  input logic [4:0] id_ex_rs1,
  input logic [4:0] id_ex_rs2,
  
  input logic [4:0] hazard_ex_rd,
  input logic hazard_ex_mem_read,
  
  input logic [4:0] fwd_ex_rd,
  input logic fwd_ex_reg_write,
  input logic [4:0] fwd_mem_rd,
  input logic fwd_mem_reg_write,
  
  input logic [1:0] forward_a,
  input logic [1:0] forward_b,
  
  input logic ex_mem_reg_write,
  input logic ex_mem_mem_write,
  input logic ex_mem_mem_read,
  input logic [31:0] ex_mem_alu_result,
  
  input logic id_ex_reg_write,
  input logic [31:0] commit_pc,
  
  input logic id_ex_mem_read,
  input logic id_ex_mem_write,
  
  input logic [6:0] id_ex_opcode,
  
  input logic [31:0] ex_operand_a,
  input logic [31:0] ex_operand_b,
  
  input logic [31:0] core_pc,
  input logic [6:0] commit_opcode
);
  
  property pc_aligned;
    @(posedge clk) disable iff (!rst_n)
    if_id_pc[1:0] == 2'b00;
  endproperty
  
  A1: assert property (pc_aligned)
    else $error("A1: PC not aligned");
    
//////////////////////////////////////       
    
    property redirect_aligned;
      @(posedge clk) disable iff(!rst_n)
      redirect_valid |-> redirect_pc[1:0] == 2'b00;
    endproperty
    
  A2: assert property (redirect_aligned)
    else $error("A2: Redirect PC not aligned");
    
//////////////////////////////////////////      
    
    property no_simul_mem;
      @(posedge clk) disable iff (!rst_n)
      !(mem_read && mem_write);
    endproperty
    
  A3: assert property (no_simul_mem)
    else $error("A3: Simultaneous memory read & write");
    
//////////////////////////////////////////      
    
    property wb_mux;
      @(posedge clk) disable iff (!rst_n)
      reg_write |->
      (mem_to_reg ? (commit_data == mem_data) : (commit_data == alu_result));
    endproperty
    
  A4: assert property (wb_mux)
    else $error("A4: Writeback mux mismatch");
    
//////////////////////////////////////////      
    
    property commit_valid_instr;
      @(posedge clk) disable iff (!rst_n)
      commit_valid |-> (commit_opcode inside {
        OPCODE_OP, OPCODE_OP_IMM, OPCODE_LOAD, OPCODE_STORE, OPCODE_BRANCH, 
        OPCODE_JAL, OPCODE_JALR, OPCODE_LUI, OPCODE_AUIPC, 7'b1110011
      });
    endproperty
    
    A5: assert property (commit_valid_instr)
      else $error("A5: Commit with unknown opcode");
    
//////////////////////////////////////////      
    
    property load_use_detected;
      @(posedge clk) disable iff (!rst_n)
      (hazard_ex_mem_read && (hazard_ex_rd != 0) 
       && ((hazard_ex_rd == id_rs1) || (hazard_ex_rd == id_rs2)))
      |-> (stall_if && stall_id && flush_ex);
    endproperty
      
  A6: assert property (load_use_detected)
    else $error("A6: Load-use hazard not stalled properly");
    
//////////////////////////////////////////      
    
    property no_false_load_stall;
      @(posedge clk) disable iff (!rst_n)
      (!(hazard_ex_mem_read &&
        (hazard_ex_rd != 0) && 
        ((hazard_ex_rd == id_rs1) || (hazard_ex_rd == id_rs2))))
      |-> !(stall_if && stall_id);
    endproperty
    
  A7: assert property (no_false_load_stall)
    else $error("A7: False load-use stall detected");
    
//////////////////////////////////////////      
    
    property ex_forward_rs1;
      @(posedge clk) disable iff (!rst_n)
      (fwd_ex_reg_write && (fwd_ex_rd != 0) && (fwd_ex_rd == id_ex_rs1)) 
      |-> (forward_a == 2'b10);
    endproperty
    
  A8: assert property (ex_forward_rs1)
    else $error("A8: EX forwarding failed for rs1");
    
//////////////////////////////////////////      
    
    property mem_forward_rs1;
      @(posedge clk) disable iff (!rst_n)
      (fwd_mem_reg_write && (fwd_mem_rd != 0) && 
       !(fwd_ex_reg_write && (fwd_ex_rd == id_ex_rs1)) && 
       (fwd_mem_rd == id_ex_rs1))
      |-> (forward_a == 2'b01);
    endproperty
    
  A9: assert property (mem_forward_rs1)
    else $error("A9: MEM forwarding failed for rs1");  
    
//////////////////////////////////////////      
    
    property ex_forward_rs2;
      @(posedge clk) disable iff (!rst_n)
      (fwd_ex_reg_write && (fwd_ex_rd != 0) && (fwd_ex_rd == id_ex_rs2))
      |-> (forward_b == 2'b10);
    endproperty
    
  A10: assert property (ex_forward_rs2)
    else $error("A10: EX forwarding failed for rs2");
    
//////////////////////////////////////////      
    
    property mem_forward_rs2;
      @(posedge clk) disable iff (!rst_n)
      (fwd_mem_reg_write && (fwd_mem_rd != 0) && 
       !(fwd_ex_reg_write && (fwd_ex_rd == id_ex_rs2)) && 
       (fwd_mem_rd == id_ex_rs2))
      |-> (forward_b == 2'b01);
    endproperty
    
  A11: assert property (mem_forward_rs2)
    else $error("A11: MEM forwarding failed for rs2"); 
    
//////////////////////////////////////////   
    
    property stall_freeze_ifid;
      @(posedge clk) disable iff (!rst_n)
      stall_if |=> $stable(if_id_pc);
    endproperty
    
  A12: assert property (stall_freeze_ifid)
    else $error("A12: PC changed during stall");
    
//////////////////////////////////////////   
    
    property flush_kills_ex;
      @(posedge clk) disable iff (!rst_n)
      (flush_ex && !redirect_valid)
      |=> (!id_ex_reg_write && !id_ex_mem_read && !id_ex_mem_write);
    endproperty
    
  A13: assert property(flush_kills_ex)
    else $error("A13: Flush did not inject bubble into ID/EX");
    
//////////////////////////////////////////   

    property commit_pc_aligned;
      @(posedge clk) disable iff (!rst_n)
      commit_valid |-> commit_pc[1:0] == 2'b00;
    endproperty
    
  A14: assert property (commit_pc_aligned)
    else $error("A14: Commit pc not aligned");
    
//////////////////////////////////////////   
    
    property redirect_has_priority;
      @(posedge clk) disable iff (!rst_n)
      (redirect_valid && !stall_if) |=> (core_pc != $past(core_pc) + 32'd4);
    endproperty
    
  A15: assert property (redirect_has_priority)
    else $error("A15: Redirect did not override PC increment");
    
//////////////////////////////////////////   
    
    property no_unnecessary_forward_rs1;
      @(posedge clk) disable iff (!rst_n)
      !(fwd_ex_reg_write && fwd_ex_rd == id_ex_rs1) &&
      !(fwd_mem_reg_write && fwd_mem_rd == id_ex_rs1)
      |-> (forward_a == 2'b00);
    endproperty
    
  A16: assert property (no_unnecessary_forward_rs1)
    else $error("A16: Unnecessary forward detected on rs1");
    
//////////////////////////////////////////   
    
    property no_ex_forward_on_load_rs1;
      @(posedge clk) disable iff (!rst_n)
      (ex_mem_mem_read && fwd_ex_rd == id_ex_rs1) |-> (forward_a != 2'b10);
    endproperty
    
    A17: assert property (no_ex_forward_on_load_rs1)
      else $error("A17: Load forward from Ex stage detected on rs1");
    
//////////////////////////////////////////   
    
    property store_no_regwrite;
      @(posedge clk) disable iff (!rst_n)
      ex_mem_mem_write |-> !ex_mem_reg_write;
    endproperty
    
  A18: assert property (store_no_regwrite)
    else $error("A18: Regwrite happened during memwrite");
    
//////////////////////////////////////////   
    
    property jump_writes;
      @(posedge clk) disable iff (!rst_n)
      (id_ex_opcode inside {OPCODE_JAL, OPCODE_JALR})
      |-> id_ex_reg_write;
    endproperty
    
  A19: assert property (jump_writes)
    else $error("A19: Jump did not enable reg_write in EX stage");
    
//////////////////////////////////////////   
    
    property flush_clears_controls;
      @(posedge clk) disable iff (!rst_n)
      (flush_ex && !redirect_valid)
      |=> (!id_ex_reg_write && !id_ex_mem_read && !id_ex_mem_write);
    endproperty
    
  A20: assert property (flush_clears_controls)
    else $error("A20: Flush did not clear EX/MEM controls");
      
//////////////////////////////////////////   
      
    property stall_freeze_idex;
      @(posedge clk) disable iff (!rst_n)
      (stall_id && !redirect_valid && !flush_ex)
      |=> $stable(id_ex_rs1) && $stable(id_ex_rs2) && $stable(id_ex_opcode);
    endproperty
    
  A21: assert property (stall_freeze_idex)
    else $error("A21: Stall did not freeze ID stage");
    
//////////////////////////////////////////   
    
    property no_ex_forward_on_load_rs2;
      @(posedge clk) disable iff (!rst_n)
      (ex_mem_mem_read && fwd_ex_rd == id_ex_rs2)
      |-> (forward_b != 2'b10);
    endproperty
    
  A22: assert property (no_ex_forward_on_load_rs2)
    else $error("A22: Load forward from EX stage detected on rs2");
    
//////////////////////////////////////////   

    property pc_increments_normally;
      @(posedge clk) disable iff (!rst_n)
      ($past(rst_n) && !stall_if && !redirect_valid)
      |=> (core_pc == $past(core_pc) + 32'd4);
    endproperty
    
  A23: assert property (pc_increments_normally)
    else $error("A23: PC did not increment correctly");
    
//////////////////////////////////////////   
    
    property redirect_updates_pc;
      @(posedge clk) disable iff (!rst_n)
      (redirect_valid && !stall_if) |=> (core_pc == $past(redirect_pc));
    endproperty
    
  A24: assert property (redirect_updates_pc)
    else $error("A24: Redirect did not update PC correctly");
    
//////////////////////////////////////////   
    
    property ex_forward_value_rs1;
      @(posedge clk) disable iff (!rst_n)
      (forward_a == 2'b10 && id_ex_opcode != OPCODE_AUIPC)
      |-> (ex_operand_a == ex_mem_alu_result);
    endproperty
    
  A25: assert property (ex_forward_value_rs1)
    else $error("A25: EX forward value incorrect for rs1");
    
//////////////////////////////////////////   
    
    property mem_forward_value_rs1;
      @(posedge clk) disable iff (!rst_n)
      (forward_a == 2'b01)
      |-> (ex_operand_a == (mem_to_reg ? mem_data : alu_result));
    endproperty
    
  A26: assert property (mem_forward_value_rs1)
    else $error("A26: MEM forward value incorrect for rs1");
    
//////////////////////////////////////////   
    
    property writeback_temporal;
      @(posedge clk) disable iff (!rst_n)
      (commit_valid && reg_write)
      |-> (commit_data == (mem_to_reg ? mem_data : alu_result));
    endproperty
    
  A27: assert property (writeback_temporal)
    else $error("A27:Writeback data incorrect temporally");
    
//////////////////////////////////////////   
    
    property stall_holds_pc;
      @(posedge clk) disable iff (!rst_n)
      stall_if |=> (core_pc == $past(core_pc));
    endproperty
    
  A28: assert property (stall_holds_pc)
    else $error("A28: PC changed during stall");
    
//////////////////////////////////////////   
    
  c1: cover property (@(posedge clk)
                      hazard_ex_mem_read && (hazard_ex_rd == id_rs1));
    
  c2: cover property (@(posedge clk)
                      forward_a == 2'b10);
      
  c3: cover property (@(posedge clk)
                      stall_if);
      
      
endmodule     
