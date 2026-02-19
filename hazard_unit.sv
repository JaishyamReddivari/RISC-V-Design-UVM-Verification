module hazard_unit
    import riscv_pkg::*;
(
    // ID stage info
    input  reg_addr_t id_rs1,
    input  reg_addr_t id_rs2,

    // EX stage info
    input  reg_addr_t ex_rd,
    input  logic      ex_mem_read,

    // Control outputs
    output logic stall_if,
    output logic stall_id,
    output logic flush_ex
);

    logic load_use_hazard;

    assign load_use_hazard =
        ex_mem_read &&
        (ex_rd != 5'd0) &&
        ((ex_rd == id_rs1) ||
         (ex_rd == id_rs2));

    assign stall_if  = load_use_hazard;
    assign stall_id  = load_use_hazard;
    assign flush_ex  = load_use_hazard;

endmodule
