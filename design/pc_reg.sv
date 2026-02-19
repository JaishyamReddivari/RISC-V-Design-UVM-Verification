module pc_reg
    import riscv_pkg::*;
(
    input  logic clk,
    input  logic rst_n,
    input  logic stall,
    input  xlen_t pc_next,
    output xlen_t pc
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc <= '0;
        else if (!stall)
            pc <= pc_next;
    end

endmodule