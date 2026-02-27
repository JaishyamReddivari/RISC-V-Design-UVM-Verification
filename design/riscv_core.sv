module riscv_core
    import riscv_pkg::*;
(
    input  logic clk,
    input  logic rst_n,

    imem_if.master imem,
    dmem_if.master dmem,
    commit_if commit
);

    // ---------------------------------
    // Pipeline Wires
    // ---------------------------------

    if_id_t  if_id;
    id_ex_t  id_ex;
    ex_mem_t ex_mem;
    mem_wb_t mem_wb;
    
    logic [31:0] ex_operand_a;
    logic [31:0] ex_operand_b;

    // ---------------------------------
    // Hazard Detection
    // ---------------------------------

    logic stall_if, stall_id, flush_ex;

    hazard_unit u_hazard (
        .id_rs1      (if_id.instr[19:15]),
        .id_rs2      (if_id.instr[24:20]),
        .ex_rd       (id_ex.rd),
        .ex_mem_read (id_ex.ctrl.mem_read),
        .stall_if    (stall_if),
        .stall_id    (stall_id),
        .flush_ex    (flush_ex)
    );

    // ---------------------------------
    // IF Stage
    // ---------------------------------

    logic redirect_valid;
    xlen_t redirect_pc;

    if_stage u_if (
        .clk            (clk),
        .rst_n          (rst_n),
        .stall          (stall_if),
        .flush          (redirect_valid),
        .redirect_valid (redirect_valid),
        .redirect_pc    (redirect_pc),
        .imem           (imem),
        .if_id_out      (if_id)
    );

    // ---------------------------------
    // ID Stage
    // ---------------------------------

    logic      wb_we;
    reg_addr_t wb_rd;
    xlen_t     wb_data;
  
    assign wb_we   = mem_wb.ctrl.reg_write;
    assign wb_rd   = mem_wb.rd;
    assign wb_data = mem_wb.ctrl.mem_to_reg ?
                     mem_wb.mem_data :
                     mem_wb.alu_result;
  
    id_stage u_id (
        .clk       (clk),
        .rst_n     (rst_n),
        .if_id_in  (if_id),
        .wb_we     (wb_we),
        .wb_rd     (wb_rd),
        .wb_data   (wb_data),
        .stall     (stall_id),
        .flush     (redirect_valid || flush_ex),
        .id_ex_out (id_ex)
    );

    // ---------------------------------
    // EX Stage
    // ---------------------------------

    ex_stage u_ex (
        .clk            (clk),
        .rst_n          (rst_n),
        .id_ex_in       (id_ex),
        .ex_mem_in      (ex_mem),
        .mem_wb_in      (mem_wb),
        .stall          (1'b0),
        .flush          (1'b0),
        .ex_mem_out     (ex_mem),
        .redirect_valid (redirect_valid),
        .redirect_pc    (redirect_pc),
        .operand_a_debug(ex_operand_a),
        .operand_b_debug(ex_operand_b)
    );

    // ---------------------------------
    // MEM Stage
    // ---------------------------------

    mem_stage u_mem (
        .clk        (clk),
        .rst_n      (rst_n),
        .ex_mem_in  (ex_mem),
        .stall      (1'b0),
        .flush      (1'b0),
        .dmem       (dmem),
        .mem_wb_out (mem_wb)
    );

  //for tb
  assign commit.valid = (mem_wb.instr != 32'b0);
  assign commit.pc    = mem_wb.pc;
  assign commit.rd    = mem_wb.rd;
  assign commit.data  = wb_data;
  assign commit.instr = mem_wb.instr;
  
endmodule
