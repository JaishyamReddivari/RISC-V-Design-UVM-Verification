module imm_generator
    import riscv_pkg::*;
(
    input  xlen_t instr,
    output xlen_t imm
);

    opcode_e opcode;

    assign opcode = instr[6:0];

    always_comb begin
        unique case (opcode)

            OPCODE_OP_IMM,
            OPCODE_LOAD,
            OPCODE_JALR: begin
                imm = {{20{instr[31]}}, instr[31:20]};
            end

            OPCODE_STORE: begin
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            end

            OPCODE_BRANCH: begin
                imm = {{19{instr[31]}},
                       instr[31],
                       instr[7],
                       instr[30:25],
                       instr[11:8],
                       1'b0};
            end

            OPCODE_LUI,
            OPCODE_AUIPC: begin
                imm = {instr[31:12], 12'b0};
            end

            OPCODE_JAL: begin
                imm = {{11{instr[31]}},
                       instr[31],
                       instr[19:12],
                       instr[20],
                       instr[30:21],
                       1'b0};
            end

            default: imm = '0;

        endcase
    end

endmodule