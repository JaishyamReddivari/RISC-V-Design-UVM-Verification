module branch_unit
    import riscv_pkg::*;
(
    input  xlen_t   rs1,
    input  xlen_t   rs2,
    input  branch_e branch_type,
    output logic    branch_taken
);

    always_comb begin
        branch_taken = 1'b0;

        unique case (branch_type)
            BR_BEQ:  branch_taken = (rs1 == rs2);
            BR_BNE:  branch_taken = (rs1 != rs2);
            BR_BLT:  branch_taken = ($signed(rs1) < $signed(rs2));
            BR_BGE:  branch_taken = ($signed(rs1) >= $signed(rs2));
            BR_BLTU: branch_taken = (rs1 < rs2);
            BR_BGEU: branch_taken = (rs1 >= rs2);
            default: branch_taken = 1'b0;
        endcase
    end

endmodule