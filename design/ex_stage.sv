module ex_stage
    import riscv_pkg::*;
(
    input  logic clk,
    input  logic rst_n,

    input  id_ex_t   id_ex_in,
    input  ex_mem_t  ex_mem_in,
    input  mem_wb_t  mem_wb_in,

    input  logic stall,
    input  logic flush,

    output ex_mem_t ex_mem_out,
    output logic    redirect_valid,
    output xlen_t   redirect_pc,
  
    output xlen_t operand_a_debug,
    output xlen_t operand_b_debug
);

    // -----------------------------
    // Forwarding
    // -----------------------------
    logic [1:0] forward_a, forward_b;

    forwarding_unit u_fwd (
        .id_ex_rs1(id_ex_in.rs1),
        .id_ex_rs2(id_ex_in.rs2),
        .ex_mem_rd(ex_mem_in.rd),
        .ex_mem_reg_write(ex_mem_in.ctrl.reg_write),
        .mem_wb_rd(mem_wb_in.rd),
        .mem_wb_reg_write(mem_wb_in.ctrl.reg_write),
        .forward_a(forward_a),
        .forward_b(forward_b)
    );

    xlen_t operand_a, operand_b_raw, operand_b;

    logic use_pc;
  assign use_pc = (id_ex_in.ctrl.alu_op == ALU_ADD) &&	
    			  (id_ex_in.instr[6:0] == OPCODE_AUIPC);
    
    // Operand A selection
    always_comb begin
      if(use_pc) begin
        operand_a = id_ex_in.pc;
      end
      else begin
        unique case (forward_a)
            2'b10: operand_a = ex_mem_in.alu_result;
            2'b01: operand_a = mem_wb_in.ctrl.mem_to_reg ?
                               mem_wb_in.mem_data :
                               mem_wb_in.alu_result;
            default: operand_a = id_ex_in.rs1_data;
        endcase
      end
    end

    // Operand B forwarding
    always_comb begin
        unique case (forward_b)
            2'b10: operand_b_raw = ex_mem_in.alu_result;
            2'b01: operand_b_raw = mem_wb_in.ctrl.mem_to_reg ?
                                   mem_wb_in.mem_data :
                                   mem_wb_in.alu_result;
            default: operand_b_raw = id_ex_in.rs2_data;
        endcase
    end

    // ALU src select
    assign operand_b = id_ex_in.ctrl.alu_src ?
                       id_ex_in.imm :
                       operand_b_raw;

    // -----------------------------
    // ALU
    // -----------------------------
    xlen_t alu_result_raw;
    xlen_t alu_result;

    alu u_alu (
        .op_a    (operand_a),
        .op_b    (operand_b),
        .alu_op  (id_ex_in.ctrl.alu_op),
      .result  (alu_result_raw)
    );
  
    always_comb begin
      alu_result = alu_result_raw;
      
      if(id_ex_in.ctrl.jump) begin
        alu_result = id_ex_in.pc + 32'd4;
      end
    end
  
    // -----------------------------
    // Branch Logic
    // -----------------------------
    logic branch_taken;

    branch_unit u_branch (
        .rs1         (operand_a),
        .rs2         (operand_b_raw),
        .branch_type (id_ex_in.ctrl.branch_type),
        .branch_taken(branch_taken)
    );

    assign redirect_valid =
        (id_ex_in.ctrl.branch && branch_taken) ||
        (id_ex_in.ctrl.jump);

     always_comb begin
       redirect_pc = '0;
       
       if(id_ex_in.ctrl.jump) begin
         if (id_ex_in.instr[6:0] == OPCODE_JALR)
         redirect_pc = (operand_a + id_ex_in.imm) & ~32'd1;
       else
         redirect_pc = id_ex_in.pc + id_ex_in.imm;
       end else if(id_ex_in.ctrl.branch && branch_taken) begin
         redirect_pc = id_ex_in.pc + id_ex_in.imm;
       end
     end

    // -----------------------------
    // EX/MEM Pipeline Register
    // -----------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ex_mem_out <= '0;
        else if (flush)
            ex_mem_out <= '0;
        else if (!stall) begin
            ex_mem_out.pc         <= id_ex_in.pc;
            ex_mem_out.alu_result <= alu_result;
            ex_mem_out.rs2_data   <= operand_b_raw;
            ex_mem_out.rd         <= id_ex_in.rd;
            ex_mem_out.ctrl       <= id_ex_in.ctrl;
            ex_mem_out.instr <= id_ex_in.instr;
        end
    end
  
  assign operand_a_debug = operand_a;
  assign operand_b_debug = operand_b_raw;
  
endmodule
