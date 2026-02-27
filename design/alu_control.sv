module alu_control
    import riscv_pkg::*;
(
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    input  opcode_e    opcode,
    output alu_op_e    alu_op,
    output branch_e    branch_type
);

    always_comb begin
        alu_op      = ALU_ADD;
        branch_type = BR_NONE;

        unique case (opcode)

            OPCODE_OP: begin
                unique case (funct3)
                    3'b000: alu_op = (funct7[5]) ? ALU_SUB : ALU_ADD;
                    3'b111: alu_op = ALU_AND;
                    3'b110: alu_op = ALU_OR;
                    3'b100: alu_op = ALU_XOR;
                    3'b010: alu_op = ALU_SLT;
                    3'b011: alu_op = ALU_SLTU;
                    3'b001: alu_op = ALU_SLL;
                    3'b101: alu_op = (funct7[5]) ? ALU_SRA : ALU_SRL;
                endcase
            end

            OPCODE_OP_IMM: begin
                unique case (funct3)
                    3'b000: alu_op = ALU_ADD;
                    3'b111: alu_op = ALU_AND;
                    3'b110: alu_op = ALU_OR;
                    3'b100: alu_op = ALU_XOR;
                    3'b010: alu_op = ALU_SLT;
                    3'b011: alu_op = ALU_SLTU;
                    3'b001: alu_op = ALU_SLL;
                    3'b101: alu_op = (funct7[5]) ? ALU_SRA : ALU_SRL;
                endcase
            end

            OPCODE_BRANCH: begin
                unique case (funct3)
                    3'b000: branch_type = BR_BEQ;
                    3'b001: branch_type = BR_BNE;
                    3'b100: branch_type = BR_BLT;
                    3'b101: branch_type = BR_BGE;
                    3'b110: branch_type = BR_BLTU;
                    3'b111: branch_type = BR_BGEU;
                endcase
            end

            default: ;

        endcase
    end

endmodule
