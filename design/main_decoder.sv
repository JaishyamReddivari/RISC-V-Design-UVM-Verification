module main_decoder
    import riscv_pkg::*;
(
    input  logic [6:0] opcode,
    output control_t   ctrl
);

    always_comb begin
        ctrl = '0;  // default safe values

        unique case (opcode)

            OPCODE_OP: begin
                ctrl.reg_write = 1;
                ctrl.alu_src   = 0;
                ctrl.alu_op    = ALU_ADD; // placeholder (real op from alu_control)
            end

            OPCODE_OP_IMM: begin
                ctrl.reg_write = 1;
                ctrl.alu_src   = 1;
                ctrl.alu_op    = ALU_ADD;
            end

            OPCODE_LOAD: begin
                ctrl.reg_write = 1;
                ctrl.mem_read  = 1;
                ctrl.mem_to_reg= 1;
                ctrl.alu_src   = 1;
                ctrl.alu_op    = ALU_ADD;
            end

            OPCODE_STORE: begin
                ctrl.mem_write = 1;
                ctrl.alu_src   = 1;
                ctrl.alu_op    = ALU_ADD;
            end

            OPCODE_BRANCH: begin
                ctrl.branch    = 1;
            end

            OPCODE_JAL,
            OPCODE_JALR: begin
                ctrl.jump      = 1;
                ctrl.reg_write = 1;
            end

            OPCODE_LUI: begin
                ctrl.reg_write = 1;
                ctrl.alu_src   = 1;
                ctrl.alu_op    = ALU_COPY_B;
            end

            OPCODE_AUIPC: begin
                ctrl.reg_write = 1;
                ctrl.alu_src   = 1;
                ctrl.alu_op    = ALU_ADD;
            end

            default: ctrl = '0;

        endcase
    end

endmodule