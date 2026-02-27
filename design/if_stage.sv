module if_stage
    import riscv_pkg::*;
(
    input  logic clk,
    input  logic rst_n,

    // Control from hazard / branch unit
    input  logic stall,
    input  logic flush,
    input  logic redirect_valid,
    input  xlen_t redirect_pc,

    // Instruction memory
    imem_if.master imem,

    // IF/ID pipeline output
    output if_id_t if_id_out
);

    xlen_t pc;
    xlen_t pc_next;

    // ------------------------
    // PC Register
    // ------------------------
    pc_reg u_pc_reg (
        .clk     (clk),
        .rst_n   (rst_n),
        .stall   (stall),
        .pc_next (pc_next),
        .pc      (pc)
    );

    // ------------------------
    // PC Next Logic
    // ------------------------
    pc_next_logic u_pc_next (
        .pc              (pc),
        .redirect_valid  (redirect_valid),
        .redirect_pc     (redirect_pc),
        .pc_next         (pc_next)
    );

    // ------------------------
    // Instruction Fetch
    // ------------------------
    assign imem.req  = 1'b1;
    assign imem.addr = pc;

    // ------------------------
    // IF/ID Pipeline Bundle
    // ------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_out <= '0;
        end
        else if (flush) begin
            if_id_out <= '0;   // inject bubble
        end
        else if (!stall) begin
            if_id_out.pc    <= pc;
            if_id_out.instr <= imem.rdata;
        end
    end

endmodule
