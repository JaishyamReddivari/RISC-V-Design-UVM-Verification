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
    output xlen_t   redirect_pc
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

    // Operand A selection
    always_comb begin
        unique case (forward_a)
            2'b10: operand_a = ex_mem_in.alu_result;
            2'b01: operand_a = mem_wb_in.ctrl.mem_to_reg ?
                               mem_wb_in.mem_data :
                               mem_wb_in.alu_result;
            default: operand_a = id_ex_in.rs1_data;
        endcase
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
    xlen_t alu_result;

    alu u_alu (
        .op_a    (operand_a),
        .op_b    (operand_b),
        .alu_op  (id_ex_in.ctrl.alu_op),
        .result  (alu_result)
    );

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
        id_ex_in.ctrl.jump;

    assign redirect_pc =
        id_ex_in.pc + id_ex_in.imm;

    // -----------------------------
    // EX/MEM Pipeline Register
    // -----------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ex_mem_out <= '0;
        else if (flush)
            ex_mem_out <= '0;
        else if (!stall) begin
            ex_mem_out.alu_result <= alu_result;
            ex_mem_out.rs2_data   <= operand_b_raw;
            ex_mem_out.rd         <= id_ex_in.rd;
            ex_mem_out.ctrl       <= id_ex_in.ctrl;
        end
    end

endmodule