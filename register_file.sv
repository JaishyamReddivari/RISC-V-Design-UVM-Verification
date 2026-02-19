module register_file
    import riscv_pkg::*;
(
    input  logic clk,
    input  logic rst_n,

    // Read ports
    input  reg_addr_t rs1_addr,
    input  reg_addr_t rs2_addr,
    output xlen_t     rs1_data,
    output xlen_t     rs2_data,

    // Write port (WB stage)
    input  logic      we,
    input  reg_addr_t rd_addr,
    input  xlen_t     rd_data
);

    xlen_t regs [REG_COUNT-1:0];

    // -------------------------
    // Write logic
    // -------------------------
    always_ff @(posedge clk) begin
        if (we && (rd_addr != 5'd0))
            regs[rd_addr] <= rd_data;
    end

    // -------------------------
    // Combinational read
    // -------------------------
    assign rs1_data = (rs1_addr == 5'd0) ? '0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0) ? '0 : regs[rs2_addr];

endmodule