package riscv_pkg;

    // ------------------------------------------------
    // Global Parameters
    // ------------------------------------------------
    parameter int XLEN = 32;
    parameter int REG_COUNT = 32;

    typedef logic [XLEN-1:0] xlen_t;
    typedef logic [4:0]      reg_addr_t;

    // ------------------------------------------------
    // RV32I Opcodes
    // ------------------------------------------------
    typedef enum logic [6:0] {
        OPCODE_LUI     = 7'b0110111,
        OPCODE_AUIPC   = 7'b0010111,
        OPCODE_JAL     = 7'b1101111,
        OPCODE_JALR    = 7'b1100111,
        OPCODE_BRANCH  = 7'b1100011,
        OPCODE_LOAD    = 7'b0000011,
        OPCODE_STORE   = 7'b0100011,
        OPCODE_OP_IMM  = 7'b0010011,
        OPCODE_OP      = 7'b0110011
    } opcode_e;

    // ------------------------------------------------
    // ALU Operations
    // ------------------------------------------------
    typedef enum logic [3:0] {
        ALU_ADD,
        ALU_SUB,
        ALU_AND,
        ALU_OR,
        ALU_XOR,
        ALU_SLT,
        ALU_SLTU,
        ALU_SLL,
        ALU_SRL,
        ALU_SRA,
        ALU_COPY_B
    } alu_op_e;

    // ------------------------------------------------
    // Branch Types
    // ------------------------------------------------
    typedef enum logic [2:0] {
        BR_NONE,
        BR_BEQ,
        BR_BNE,
        BR_BLT,
        BR_BGE,
        BR_BLTU,
        BR_BGEU
    } branch_e;

    // ------------------------------------------------
    // Control Bundle
    // ------------------------------------------------
    typedef struct packed {
        logic        reg_write;
        logic        mem_read;
        logic        mem_write;
        logic        mem_to_reg;
        logic        alu_src;
        logic        branch;
        logic        jump;
        alu_op_e     alu_op;
        branch_e     branch_type;
    } control_t;

    // ------------------------------------------------
    // Pipeline Bundles
    // ------------------------------------------------

    typedef struct packed {
        xlen_t pc;
        xlen_t instr;
    } if_id_t;

    typedef struct packed {
        xlen_t pc;
        xlen_t rs1_data;
        xlen_t rs2_data;
        xlen_t imm;
        reg_addr_t rs1;
        reg_addr_t rs2;
        reg_addr_t rd;
        xlen_t instr;
        control_t ctrl;
    } id_ex_t;

    typedef struct packed {
        xlen_t pc;
        xlen_t alu_result;
        xlen_t rs2_data;
        reg_addr_t rd;
        xlen_t instr;
        control_t ctrl;
    } ex_mem_t;

    typedef struct packed {
        xlen_t pc;
        xlen_t alu_result;
        xlen_t mem_data;
        reg_addr_t rd;
        xlen_t instr;
        control_t ctrl;
    } mem_wb_t;

endpackage
