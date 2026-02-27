module forwarding_unit
    import riscv_pkg::*;
(
    input  reg_addr_t id_ex_rs1,
    input  reg_addr_t id_ex_rs2,

    input  reg_addr_t ex_mem_rd,
    input  logic      ex_mem_reg_write,

    input  reg_addr_t mem_wb_rd,
    input  logic      mem_wb_reg_write,

    output logic [1:0] forward_a,
    output logic [1:0] forward_b
);

    // 00 = normal
    // 01 = MEM/WB
    // 10 = EX/MEM

    always_comb begin
        forward_a = 2'b00;
        forward_b = 2'b00;

        // EX hazard
        if (ex_mem_reg_write &&
            (ex_mem_rd != 5'd0) &&
            (ex_mem_rd == id_ex_rs1))
                forward_a = 2'b10;

        if (ex_mem_reg_write &&
            (ex_mem_rd != 5'd0) &&
            (ex_mem_rd == id_ex_rs2))
                forward_b = 2'b10;

        // MEM hazard (lower priority)
        if (mem_wb_reg_write &&
            (mem_wb_rd != 5'd0) &&
            !(ex_mem_reg_write &&
              (ex_mem_rd != 5'd0) &&
              (ex_mem_rd == id_ex_rs1)) &&
            (mem_wb_rd == id_ex_rs1))
                forward_a = 2'b01;

        if (mem_wb_reg_write &&
            (mem_wb_rd != 5'd0) &&
            !(ex_mem_reg_write &&
              (ex_mem_rd != 5'd0) &&
              (ex_mem_rd == id_ex_rs2)) &&
            (mem_wb_rd == id_ex_rs2))
                forward_b = 2'b01;

    end

endmodule
