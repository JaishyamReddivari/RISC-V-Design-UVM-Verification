module mem_stage
    import riscv_pkg::*;
(
    input  logic clk,
    input  logic rst_n,

    input  ex_mem_t ex_mem_in,

    input  logic stall,
    input  logic flush,

    // Data memory interface
    dmem_if.master dmem,

    output mem_wb_t mem_wb_out
);

    // ---------------------------------
    // Memory Request Signals
    // ---------------------------------

    assign dmem.valid = ex_mem_in.ctrl.mem_read |
                        ex_mem_in.ctrl.mem_write;

    assign dmem.write = ex_mem_in.ctrl.mem_write;

    assign dmem.addr  = ex_mem_in.alu_result;
    assign dmem.wdata = ex_mem_in.rs2_data;

    // For now assume full word access
    assign dmem.wstrb = ex_mem_in.ctrl.mem_write ? 4'b1111 : 4'b0000;

    // ---------------------------------
    // Load Data (no byte/half support yet)
    // ---------------------------------

    xlen_t mem_data;

    assign mem_data = dmem.rdata;

    // ---------------------------------
    // MEM/WB Pipeline Register
    // ---------------------------------

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mem_wb_out <= '0;
        else if (flush)
            mem_wb_out <= '0;
        else if (!stall) begin
            mem_wb_out.alu_result <= ex_mem_in.alu_result;
            mem_wb_out.mem_data   <= mem_data;
            mem_wb_out.rd         <= ex_mem_in.rd;
            mem_wb_out.ctrl       <= ex_mem_in.ctrl;
        end
    end

endmodule