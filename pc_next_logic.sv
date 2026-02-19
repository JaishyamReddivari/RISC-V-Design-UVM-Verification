module pc_next_logic
    import riscv_pkg::*;
(
    input  xlen_t pc,
    input  logic  redirect_valid,
    input  xlen_t redirect_pc,
    output xlen_t pc_next
);

    always_comb begin
        if (redirect_valid)
            pc_next = redirect_pc;
        else
            pc_next = pc + 32'd4;
    end

endmodule