module alu
    import riscv_pkg::*;
(
    input  xlen_t    op_a,
    input  xlen_t    op_b,
    input  alu_op_e  alu_op,
    output xlen_t    result
);

    always_comb begin
        unique case (alu_op)

            ALU_ADD:   result = op_a + op_b;
            ALU_SUB:   result = op_a - op_b;
            ALU_AND:   result = op_a & op_b;
            ALU_OR:    result = op_a | op_b;
            ALU_XOR:   result = op_a ^ op_b;
            ALU_SLT:   result = ($signed(op_a) < $signed(op_b));
            ALU_SLTU:  result = (op_a < op_b);
            ALU_SLL:   result = op_a << op_b[4:0];
            ALU_SRL:   result = op_a >> op_b[4:0];
            ALU_SRA:   result = $signed(op_a) >>> op_b[4:0];
            ALU_COPY_B:result = op_b;

            default:   result = '0;

        endcase
    end

endmodule
