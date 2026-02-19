module id_stage
    import riscv_pkg::*;
(
    input  logic clk,
    input  logic rst_n,

    input  if_id_t  if_id_in,

    // WB stage interface
    input  logic      wb_we,
    input  reg_addr_t wb_rd,
    input  xlen_t     wb_data,

    // Control
    input  logic stall,
    input  logic flush,

    output id_ex_t id_ex_out
);

    // -----------------------------
    // Field Extraction
    // -----------------------------
    logic [4:0] rs1, rs2, rd;
    logic [2:0] funct3;
    logic [6:0] funct7;
    opcode_e    opcode;

    assign rd     = if_id_in.instr[11:7];
    assign rs1    = if_id_in.instr[19:15];
    assign rs2    = if_id_in.instr[24:20];
    assign funct3 = if_id_in.instr[14:12];
    assign funct7 = if_id_in.instr[31:25];
    assign opcode = opcode_e'(if_id_in.instr[6:0]);

    // -----------------------------
    // Register File
    // -----------------------------
    xlen_t rs1_data, rs2_data;

    register_file u_rf (
        .clk       (clk),
        .rst_n     (rst_n),
        .rs1_addr  (rs1),
        .rs2_addr  (rs2),
        .rs1_data  (rs1_data),
        .rs2_data  (rs2_data),
        .we        (wb_we),
        .rd_addr   (wb_rd),
        .rd_data   (wb_data)
    );

    // -----------------------------
    // Immediate Generator
    // -----------------------------
    xlen_t imm;

    imm_generator u_imm (
        .instr (if_id_in.instr),
        .imm   (imm)
    );

    // -----------------------------
    // Control Logic
    // -----------------------------
    control_t ctrl_main;
    alu_op_e  alu_op;
    branch_e  branch_type;

    main_decoder u_main_dec (
        .opcode (if_id_in.instr[6:0]),
        .ctrl   (ctrl_main)
    );

    alu_control u_alu_ctrl (
        .funct3      (funct3),
        .funct7      (funct7),
        .opcode      (opcode),
        .alu_op      (alu_op),
        .branch_type (branch_type)
    );

    // Override ALU op from second level
    control_t ctrl_final;

    always_comb begin
        ctrl_final = ctrl_main;
        ctrl_final.alu_op = alu_op;
        ctrl_final.branch_type = branch_type;
    end

    // -----------------------------
    // ID/EX Pipeline Register
    // -----------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            id_ex_out <= '0;
        else if (flush)
            id_ex_out <= '0;
        else if (!stall) begin
            id_ex_out.pc        <= if_id_in.pc;
            id_ex_out.rs1_data  <= rs1_data;
            id_ex_out.rs2_data  <= rs2_data;
            id_ex_out.imm       <= imm;
            id_ex_out.rs1       <= rs1;
            id_ex_out.rs2       <= rs2;
            id_ex_out.rd        <= rd;
            id_ex_out.ctrl      <= ctrl_final;
        end
    end

endmodule