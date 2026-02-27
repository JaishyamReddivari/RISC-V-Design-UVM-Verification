`include "uvm_macros.svh"
`include "riscv_assertions.sv"
`include "riscv_bind.sv"
import uvm_pkg::*;
import riscv_pkg::*;

localparam logic [31:0] EBREAK_INSTR = 32'h00100073;

//Transaction
class riscv_transaction extends uvm_sequence_item;

  `uvm_object_utils(riscv_transaction)

  typedef enum{
    R_TYPE,
    I_TYPE,
    LOAD_TYPE,
    STORE_TYPE,
    BRANCH_TYPE,
    JAL_TYPE,
    JALR_TYPE,
    LUI_TYPE,
    AUIPC_TYPE
  } instr_types;
  
  rand instr_types instr_type;
  
  rand bit [6:0] opcode;
  rand bit [4:0] rs1, rs2, rd;
  rand bit [2:0] funct3;
  rand bit [6:0] funct7;
  rand bit signed [31:0] imm;

  bit [31:0] instr;

  function new(input string path = "riscv_transaction");
    super.new(path);
  endfunction
  
  constraint imm_c {
    if(instr_type == R_TYPE) {
      imm == 0;
    }
      
    if(instr_type == I_TYPE) {
      imm inside {[-2048:2047]};
    }
        
	if(instr_type == LOAD_TYPE) {
      rs1 == 0;
      imm inside {[0:4092]};
      imm[1:0] == 2'b00;
    }
      
	if(instr_type == STORE_TYPE) {
      rs1 == 0;
      imm inside {[0:4092]};
      imm[1:0] == 2'b00;
    }
      
	if(instr_type == BRANCH_TYPE) {
      imm inside {[-2048:2022]};
      imm[1:0] == 2'b00;
    }
      
	if(instr_type == JAL_TYPE) {
      imm inside {[-2048:2044]};
      imm[1:0] == 2'b00;
      imm != 0;
    }
      
	if(instr_type == JALR_TYPE) {
      rs1 != 0;
      rs1 inside {[0:10]};
      imm inside {[-2048:2044]};
      imm[1:0] == 2'b00;
      imm != 0;
    }
      
	if(instr_type == LUI_TYPE) {
      imm inside {[0:1048575]};
    }
      
	if(instr_type == AUIPC_TYPE) {
      imm inside {[-2048:2044]};
      imm[1:0] == 2'b00;
    }
  }
  
  constraint instr_c {
    instr_type dist {
      R_TYPE      := 20,
      I_TYPE      := 20,
      LOAD_TYPE   := 10,
      STORE_TYPE  := 10,
      BRANCH_TYPE := 15,
      JAL_TYPE    := 5,
      JALR_TYPE   := 5,
      LUI_TYPE    := 7,
      AUIPC_TYPE  := 8
    };
  }
   
  constraint opcode_c {
    
    (instr_type == R_TYPE)      -> opcode == 7'b0110011;
    (instr_type == I_TYPE)      -> opcode == 7'b0010011;
    (instr_type == LOAD_TYPE)   -> opcode == 7'b0000011;
    (instr_type == STORE_TYPE)  -> opcode == 7'b0100011;
    (instr_type == BRANCH_TYPE) -> opcode == 7'b1100011;
    (instr_type == JAL_TYPE)    -> opcode == 7'b1101111;
    (instr_type == JALR_TYPE)   -> opcode == 7'b1100111;
    (instr_type == LUI_TYPE)    -> opcode == 7'b0110111;
    (instr_type == AUIPC_TYPE)  -> opcode == 7'b0010111;
    
  }

  constraint rtype_c {
    if(instr_type == R_TYPE) {
      funct3 dist {
        3'b000 := 2,
        3'b111 := 2,
        3'b110 := 2,
        3'b100 := 2,
        3'b010 := 2,
        3'b011 := 2,
        3'b001 := 2,
        3'b101 := 2
      };
      
      if(funct3 == 3'b000)
        funct7 dist {7'b0000000 := 1, 7'b0100000 := 1}; // ADD/SUB
      else if(funct3 == 3'b101)
        funct7 dist {7'b0000000 := 1, 7'b0100000 := 1}; // SRL/SRA
      else 
        funct7 == 7'b0000000;
    }
  }
      
  constraint itype_c {
    if(instr_type == I_TYPE) {
      funct3 inside {3'b000, 3'b111, 3'b110, 3'b100,
                     3'b010, 3'b011, 3'b001, 3'b101};
      imm[31:12] == {20{imm[11]}}; // Sign extended 12-bit
      imm dist {
        [-16:-1]    := 5,
        [0:16]      := 2,
        [-2048:-17] := 1,
        [17:2047]   := 1
      };
    }
  }
  
  constraint load_c {
    if(instr_type == LOAD_TYPE) {
      funct3 == 3'b010;
      imm[31:12] == {20{imm[11]}};
    }
  }
      
  constraint store_c {
    if(instr_type == STORE_TYPE) {
      funct3 == 3'b010;
      imm[31:12] == {20{imm[11]}};
    }
  }
      
  constraint branch_c {
    if(instr_type == BRANCH_TYPE) {
      funct3 inside {3'b000, 3'b001, 3'b100,
                     3'b101, 3'b110, 3'b111};
      imm[0] == 0;
    }
  }
      
  constraint jal_c {
    if(instr_type == JAL_TYPE) {
      imm[31:21] == {20{imm[11]}};
      imm != 0;
    }
  }
      
  constraint jalr_c {
    if(instr_type == JALR_TYPE) {
      rs1 != 0;
      imm[31:12] == {20{imm[11]}};
      imm != 0;
    }
  }
          
  function void post_randomize();

    case(instr_type)
      
      R_TYPE:
        instr = {funct7, rs2, rs1, funct3, rd, opcode};
      
      I_TYPE, LOAD_TYPE, JALR_TYPE:
        instr = {imm[11:0], rs1, funct3, rd, opcode};
      
      STORE_TYPE:
        instr = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
      
      BRANCH_TYPE:
        instr = {imm[12], imm[10:5], rs2, rs1, funct3, 
                 imm[4:1], imm[11], opcode};
      
      LUI_TYPE, AUIPC_TYPE:
        instr = {imm[31:12], rd, opcode};
      
      JAL_TYPE:
        instr = {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};
      
    endcase

  endfunction

endclass

//Sequence
class riscv_sequence extends uvm_sequence #(riscv_transaction);
  `uvm_object_utils(riscv_sequence)
  
  bit [31:0] program_mem [0:1023];
  int prog_size;
  
  bit use_fixed_type = 0;
  riscv_transaction::instr_types fixed_type;
  
  bit dependency_mode = 0;
  bit load_use_stress = 0;
  bit [4:0] last_rd;
  
  int unsigned num_trans = 200;
  int base_addr = 0;
  
  function new(input string path = "riscv_sequence");
    super.new(path);
  endfunction
  
  virtual task body();
    riscv_transaction dep_tr;
    riscv_transaction tr;
    
    int pc = 0;
    int max_pc;
    int i = 0;
    
    max_pc = num_trans * 4;
    
    foreach(program_mem[j])
      program_mem[j] = 32'h00000013;
    
    while(i < num_trans) begin
      
      if(load_use_stress && (i < num_trans-1)) begin
        tr = riscv_transaction::type_id::create($sformatf("tr_%0d", i));
        assert(tr.randomize() with {instr_type == LOAD_TYPE;});
        adjust_control_flow(tr, pc, max_pc);
        start_item(tr);
        finish_item(tr);
        pc += 4;
        if(tr.rd != 0) last_rd = tr.rd;
        i++;
        
        dep_tr = riscv_transaction::type_id::create($sformatf("dep_tr_%0d", i));
        //if(tr.rd == 0) tr.rd = 5'd5;
        if(tr.rd == 0) last_rd = 5'd5;
          assert(dep_tr.randomize() with {
            instr_type inside {R_TYPE, I_TYPE};
            rs1 == last_rd;
        });
        adjust_control_flow(dep_tr, pc, max_pc);
        start_item(dep_tr);
        finish_item(dep_tr);
        pc += 4;
        if(dep_tr.rd != 0) last_rd = dep_tr.rd;
        i++;
        continue;
      end
      
      tr = riscv_transaction::type_id::create($sformatf("tr_%0d", i));
      
      if(use_fixed_type) begin
        assert(tr.randomize() with { instr_type == fixed_type; });
      end else if(dependency_mode && last_rd != 0) begin
        if(i % 2 == 0)
          assert(tr.randomize() with {rs1 == last_rd;});
        else
          assert(tr.randomize() with {rs2 == last_rd;});    
      end else begin
        assert(tr.randomize());
      end
	
      adjust_control_flow(tr, pc, max_pc);
      start_item(tr);
      finish_item(tr);
      pc += 4;
      if(tr.rd != 0) last_rd = tr.rd;
      i++;
      
    end
  endtask
  
  function void adjust_control_flow(
    ref riscv_transaction tr,
    int pc,
    int max_pc
  );
    
    int target;
    
    case(tr.instr_type)
      
      riscv_transaction::BRANCH_TYPE: begin
        target = pc + tr.imm;
        if(target < pc || target >= max_pc) begin
            tr.imm = 8;
          end
          tr.post_randomize();
      end
      
      riscv_transaction::JAL_TYPE: begin
        target = pc + tr.imm;
        if(target <= pc || target >= max_pc) begin
          tr.imm = 8;
          tr.post_randomize();
        end
      end
      
      riscv_transaction::JALR_TYPE: begin
        int abs_pc;
        tr.rs1 = 0;
        abs_pc = base_addr + pc;
        target = tr.imm;
        if(target <= abs_pc || target >= (base_addr + max_pc)) begin
          if(abs_pc + 8 < (base_addr + max_pc) && abs_pc + 8 < 2048)
            tr.imm = abs_pc + 8;
          else
            tr.imm = base_addr + max_pc;
          tr.imm = tr.imm & ~32'd1;
          //tr.post_randomize();
        end
        tr.post_randomize();
      end
      
      default: ;
    endcase
  endfunction
    
endclass

//Sequencer
class riscv_sequencer extends uvm_sequencer #(riscv_transaction);
  `uvm_component_utils(riscv_sequencer)
  
  function new(input string path = "riscv_sequencer", uvm_component parent);
    super.new(path, parent);
  endfunction
  
endclass

//IMEM_Driver
class imem_driver extends uvm_driver #(riscv_transaction);
  `uvm_component_utils(imem_driver)
  
  function new(input string path = "imem_driver", uvm_component parent);
    super.new(path, parent);
  endfunction
  
  virtual imem_if vif;
  riscv_transaction tr;
  bit [31:0] instr_mem [0:1023];
  int load_addr = 0;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    tr = riscv_transaction::type_id::create("tr");
    
    if(!uvm_config_db#(virtual imem_if)::get(this, "", "vif", vif))
      `uvm_error("IMEM_DRV", "Unable to access imem_if");
  endfunction
  
  task reset();
    foreach(instr_mem[i])
      instr_mem[i] = EBREAK_INSTR;
    load_addr = 0;
    
  endtask
  
  task run_phase(uvm_phase phase);
    
    reset();
    vif.ready <= 1'b1;
    
    fork
      forever begin
        seq_item_port.get_next_item(tr);
        if(load_addr < 1024) begin
          instr_mem[load_addr] = tr.instr;
          load_addr++;
        end else begin
          `uvm_error("IMEM_DRV", "Instruction memory overflow")
        end
      seq_item_port.item_done();
    end
    
    forever begin
      @(posedge vif.clk);
      #1;
      
      if(vif.req) begin
        if((vif.addr >> 2) < 1024)
          vif.rdata = instr_mem[vif.addr >> 2];
        else
          vif.rdata = EBREAK_INSTR;
      end
    end
      
    join
  endtask
endclass

//DMEM_Driver
class dmem_driver extends uvm_driver;
  `uvm_component_utils(dmem_driver)
  
  virtual dmem_if dif;
  
  bit [31:0] data_mem [0:1023];
  
  function new(input string path = "dmem_driver", uvm_component parent);
    super.new(path, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if(!uvm_config_db#(virtual dmem_if)::get(this, "", "dif", dif))
      `uvm_error("DMEM_DRV", "Unable to access dmem_if");
  endfunction
    
  task reset();
  foreach(data_mem[i])
    data_mem[i] = 32'h0;
  endtask
  
    task run_phase(uvm_phase phase);
      
      reset();
      
      dif.ready <= 1'b1;
      
      forever begin
        @(posedge dif.clk);
        #1;
        
        if(dif.valid) begin
          
          if(dif.write) begin
            
            if((dif.addr >> 2) < 1024) begin
              data_mem[dif.addr >> 2] = dif.wdata;
            end else begin
              `uvm_error("DMEM_DRV", "Address out of range(store)")
            end
        end else begin
          
          if((dif.addr >> 2) < 1024) begin
            dif.rdata = data_mem[dif.addr >> 2];
          end else begin
            dif.rdata = 32'h0;
            `uvm_error("DMEM_DRV", "Address out of range(load)")
          end
        end
        end
        else begin
              dif.rdata = 32'h0;
        end
      end
    endtask
    
endclass
    
//Commit Transaction
class commit_tr extends uvm_sequence_item;
  `uvm_object_utils(commit_tr)
  
  bit valid;
  bit [31:0] pc;
  bit [4:0] rd;
  bit [31:0] data;
  bit [31:0] instr;
  bit [1:0] forward_a, forward_b;
  bit stall_if, flush_ex, redirect_valid;
  
  function new(input string path = "commit_tr");
    super.new(path);
  endfunction
  
endclass
      
//Monitor
class riscv_monitor extends uvm_monitor;
  `uvm_component_utils(riscv_monitor)
  
  virtual commit_if cif;
  uvm_analysis_port #(commit_tr) send;
  
  event program_done;
  
  function new(input string path = "riscv_monitor", uvm_component parent);
    super.new(path, parent);
    send = new("send", this);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if(!uvm_config_db#(virtual commit_if)::get(this, "", "cif", cif))
      `uvm_error("MON", "Unable to access uvm_config_db");
  endfunction
  
  task run_phase(uvm_phase phase);
    commit_tr ctr;
    
    forever begin
      @(posedge cif.clk);
      
      if(cif.valid) begin
        if(cif.instr == EBREAK_INSTR) begin
          `uvm_info("MON", $sformatf("EBREAK retired at PC=%08h", cif.pc), UVM_LOW)
          -> program_done;
          continue;
        end
        
        ctr = commit_tr::type_id::create("ctr");
        ctr.valid = 1'b1;
        ctr.pc = cif.pc;
        ctr.rd = cif.rd;
        ctr.data = cif.data;
        ctr.instr = cif.instr;
        
        `uvm_info("MON", $sformatf("PC=%08h, Instr=%08h, rd=%0d, data=%08h",
                                   ctr.pc, ctr.instr, ctr.rd, ctr.data), 
                  UVM_HIGH)
        
        send.write(ctr);
      end
    end
  endtask
  
endclass
    
//Exec Monitor for coverage
class riscv_exec_monitor extends uvm_monitor;
  `uvm_component_utils(riscv_exec_monitor)
  
  virtual exec_if eif;
  uvm_analysis_port #(commit_tr) send_exec;
  
  function new(input string path = "riscv_exec_monitor", uvm_component parent);
    super.new(path, parent);
    
    send_exec = new("send_exec", this);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if(!uvm_config_db#(virtual exec_if)::get(this, "", "eif", eif))
      `uvm_error("EXEC_MON", "Unable to get exec_if");
  endfunction
  
  task run_phase(uvm_phase phase);
    commit_tr ct;
    
    forever begin
      @(posedge eif.clk);
      if(eif.valid) begin
        ct = commit_tr::type_id::create("ct");
        
        ct.instr = eif.instr;
        ct.pc = eif.pc;
        
        ct.forward_a = eif.forward_a;
        ct.forward_b = eif.forward_b;
        
        ct.stall_if = eif.stall_if;
        ct.flush_ex = eif.flush_ex;
        ct.redirect_valid = eif.redirect_valid;
        
        send_exec.write(ct);
      end
    end
  endtask
endclass
    
//Scoreboard
class riscv_scoreboard extends uvm_scoreboard;    
  `uvm_component_utils(riscv_scoreboard)
  
  uvm_analysis_imp #(commit_tr, riscv_scoreboard) recv_c;
  
  logic [31:0] ref_reg [0:31];
  logic [31:0] ref_mem [0:1023];
  logic [31:0] ref_pc;
  int pass_count, fail_count;
  
  function new(input string path = "riscv_scoreboard", uvm_component parent);
    super.new(path, parent);
    recv_c = new("recv_c", this);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    reset_state();
  endfunction
  
  virtual function void reset_state();
    ref_pc = 0;
    foreach (ref_reg[i]) ref_reg[i] = 0;
    foreach (ref_mem[i]) ref_mem[i] = 0;
  endfunction
  
  virtual function void write(commit_tr ct);
    
    if(ct.pc !== ref_pc) begin
      `uvm_error("SCO", $sformatf("PC Mismatch, expected=%08h, got=%08h",
                                  ref_pc, ct.pc))
    end
    
    //`uvm_info("PC_DBG", $sformatf("REF_PC=%08h DUT_PC=%08h INSTR=%08h",ref_pc, ct.pc, ct.instr), UVM_LOW)
    
    execute_instruction(ct);
  endfunction
  
  function void execute_instruction(commit_tr ct);
    
    logic [31:0] instr = ct.instr;
    logic [6:0] opcode = instr[6:0];
    logic [4:0] rs1    = instr[19:15];
    logic [4:0] rs2    = instr[24:20];
    logic [4:0] rd     = instr[11:7];
    logic [2:0] funct3 = instr[14:12];
    logic [6:0] funct7 = instr[31:25];
    logic [31:0] imm;
    logic [31:0] result;
    logic branch_taken = 0;
    
    case(opcode)

      7'b0110011: begin // R-type
        case(funct3)
          3'b000: result = (funct7[5]) ?
                           (ref_reg[rs1] - ref_reg[rs2]) :
                           (ref_reg[rs1] + ref_reg[rs2]);
          3'b111: result = ref_reg[rs1] & ref_reg[rs2];
          3'b110: result = ref_reg[rs1] | ref_reg[rs2];
          3'b100: result = ref_reg[rs1] ^ ref_reg[rs2];
          3'b010: result = ($signed(ref_reg[rs1]) < $signed(ref_reg[rs2]));
          3'b011: result = (ref_reg[rs1] < ref_reg[rs2]);
          3'b001: result = ref_reg[rs1] << ref_reg[rs2][4:0];
          //3'b101: result = funct7[5] ? ($signed(ref_reg[rs1]) >>> ref_reg[rs2][4:0]) : (ref_reg[rs1] >> ref_reg[rs2][4:0]);
          3'b101: begin
            if(funct7[5]) begin
              int signed sv;
              sv = ref_reg[rs1];
              result = sv >>> ref_reg[rs2][4:0];
            end else
              result = ref_reg[rs1] >> ref_reg[rs2][4:0];
          end
          default: result = 0;
        endcase
        
        check_and_write(rd, result, ct.data);
        ref_pc = ct.pc + 4;
      end
      
      7'b0010011: begin // I-Type
        imm = {{20{instr[31]}}, instr[31:20]};
        
        case(funct3)
          3'b000: result = ref_reg[rs1] + imm;
          3'b111: result = ref_reg[rs1] & imm;
          3'b110: result = ref_reg[rs1] | imm;
          3'b100: result = ref_reg[rs1] ^ imm;
          3'b010: result = ($signed(ref_reg[rs1]) < ($signed(imm)));
          3'b011: result = (ref_reg[rs1] < imm);
          3'b001: result = ref_reg[rs1] << instr[24:20];
          //3'b101: result = funct7[5] ? ($signed(ref_reg[rs1]) >>> instr[24:20]) :(ref_reg[rs1] >> instr[24:20]);
          3'b101: begin
            if(funct7[5]) begin
              int signed sv;
              sv = ref_reg[rs1];
              result = sv >>> instr[24:20];
            end else
              result = ref_reg[rs1] >> instr[24:20];
          end
        endcase
        check_and_write(rd, result, ct.data);
        ref_pc = ct.pc + 4;
    end
                            
      7'b0000011: begin // Load Type
        imm = {{20{instr[31]}}, instr[31:20]};
        result = ref_mem[(ref_reg[rs1] + imm) >> 2];
        check_and_write(rd, result, ct.data);
        ref_pc = ct.pc + 4;
      end
                            
      7'b0100011: begin // Store Type
        imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
        ref_mem[(ref_reg[rs1] + imm) >> 2] = ref_reg[rs2];
        ref_pc = ct.pc + 4;
      end
                            
      7'b1100011: begin // Branch Type
        imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
        
        case(funct3)
          3'b000: branch_taken = (ref_reg[rs1] == ref_reg[rs2]);
          3'b001: branch_taken = (ref_reg[rs1] != ref_reg[rs2]);
          3'b100: branch_taken = ($signed(ref_reg[rs1]) < $signed(ref_reg[rs2]));
          3'b101: branch_taken = ($signed(ref_reg[rs1]) >= $signed(ref_reg[rs2]));
          3'b110: branch_taken = (ref_reg[rs1] < ref_reg[rs2]);
          3'b111: branch_taken = (ref_reg[rs1] >= ref_reg[rs2]);
        endcase
        ref_pc = branch_taken ? (ct.pc + imm) : (ct.pc + 4);
      end
                            
      7'b1101111: begin // JAL Type
        imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
        result = ct.pc + 4;
        check_and_write(rd, result, ct.data);
        ref_pc = ct.pc + imm;
      end
                            
      7'b1100111: begin // JALR Type
        imm = {{20{instr[31]}}, instr[31:20]};
        result = ct.pc + 4;
        ref_pc = (ref_reg[rs1] + imm) & ~1;
        check_and_write(rd, result, ct.data);
        //ref_pc = (ref_reg[rs1] + imm) & ~1;
      end
                            
      7'b0110111: begin // LUI Type
        result = {instr[31:12], 12'b0};
        check_and_write(rd, result, ct.data);
        ref_pc = ct.pc + 4;
      end
                            
      7'b0010111: begin // AUIPC
        result = ct.pc + {instr[31:12], 12'b0};
        check_and_write(rd, result, ct.data);
        ref_pc = ct.pc + 4;
      end
                            
      default: begin
        ref_pc = ct.pc + 4;
      end
  endcase
                            
  ref_reg[0] = 0;

  endfunction
                            
  function void check_and_write(
    logic [4:0] rd,
    logic [31:0] expected,
    logic [31:0] actual
  );
    
    if(rd != 0) begin
      if(expected != actual) begin
        `uvm_error("SCO", $sformatf("Mismatch rd=%0d, expected=%08h, got=%08h",
                                    rd, expected, actual));
        fail_count++;
      end else begin
        //`uvm_info("SCO", $sformatf("Match rd=%0d, expected=%08h, got=%08h",rd, expected, actual), UVM_NONE);
        pass_count++;
      end
      ref_reg[rd] = expected;
    end
  endfunction
  
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCO", $sformatf("Results: %0d passed, %0d failed", pass_count, fail_count), UVM_NONE)
  endfunction
endclass
    
//Coverage
class riscv_coverage extends uvm_component;
  `uvm_component_utils(riscv_coverage)
  
  uvm_analysis_imp #(commit_tr, riscv_coverage) cov_recv;
  
  bit [31:0] instr;
  bit [6:0] opcode;
  bit [2:0] funct3;
  bit [6:0] funct7;
  bit [4:0] rs1, rs2, rd;
  bit signed [31:0] imm;
  bit [1:0] forward_a, forward_b;
  bit stall_if, flush_ex, redirect_valid;
  bit [6:0] prev_opcode;
  bit [4:0] prev_rd;
  bit prev_valid;
  bit [2:0] prev_funct3;
  bit [31:0] prev_imm;
  bit [6:0] prev_opcode_mem;
  bit [31:0] prev_store_addr;
  bit prev_was_store;
 
  covergroup cov_opcode();
    
    option.per_instance = 1;
    
    cp_opcode : coverpoint opcode {
      bins R_TYPE      = {7'b0110011};
      bins I_TYPE      = {7'b0010011};
      bins LOAD_TYPE   = {7'b0000011};
      bins STORE_TYPE  = {7'b0100011};
      bins BRANCH_TYPE = {7'b1100011};
      bins JAL_TYPE    = {7'b1101111};
      bins JALR_TYPE   = {7'b1100111};
      bins LUI_TYPE    = {7'b0110111};
      bins AUIPC_TYPE  = {7'b0010111};
      
      illegal_bins illegal_opcode = default;
    }
    
    cp_funct3 : coverpoint funct3 {
      bins f3_vals[] = {[0:7]};
    }
    
    opcode_funct3_cross : cross cp_opcode, cp_funct3 {
      
      ignore_bins no_f3_jal   = binsof(cp_opcode) intersect {7'b1101111};
      ignore_bins no_f3_lui   = binsof(cp_opcode) intersect {7'b0110111};
      ignore_bins no_f3_auipc = binsof(cp_opcode) intersect {7'b0010111};
      
      ignore_bins load_f0 = binsof(cp_opcode) intersect {7'b0000011} &&
                            binsof(cp_funct3) intersect {3'b000};
      ignore_bins load_f1 = binsof(cp_opcode) intersect {7'b0000011} &&
                            binsof(cp_funct3) intersect {3'b001};
      ignore_bins load_f3 = binsof(cp_opcode) intersect {7'b0000011} &&
                            binsof(cp_funct3) intersect {3'b011};
      ignore_bins load_f4 = binsof(cp_opcode) intersect {7'b0000011} &&
                            binsof(cp_funct3) intersect {3'b100};
      ignore_bins load_f5 = binsof(cp_opcode) intersect {7'b0000011} &&
                            binsof(cp_funct3) intersect {3'b101};
      ignore_bins load_f6 = binsof(cp_opcode) intersect {7'b0000011} &&
                            binsof(cp_funct3) intersect {3'b110};
      ignore_bins load_f7 = binsof(cp_opcode) intersect {7'b0000011} &&
                            binsof(cp_funct3) intersect {3'b111};
      
      ignore_bins store_f0 = binsof(cp_opcode) intersect {7'b0100011} &&
                             binsof(cp_funct3) intersect {3'b000};
      ignore_bins store_f1 = binsof(cp_opcode) intersect {7'b0100011} &&
                             binsof(cp_funct3) intersect {3'b001};
      ignore_bins store_f3 = binsof(cp_opcode) intersect {7'b0100011} &&
                             binsof(cp_funct3) intersect {3'b011};
      ignore_bins store_f4 = binsof(cp_opcode) intersect {7'b0100011} &&
                             binsof(cp_funct3) intersect {3'b100};
      ignore_bins store_f5 = binsof(cp_opcode) intersect {7'b0100011} &&
                             binsof(cp_funct3) intersect {3'b101};
      ignore_bins store_f6 = binsof(cp_opcode) intersect {7'b0100011} &&
                             binsof(cp_funct3) intersect {3'b110};
      ignore_bins store_f7 = binsof(cp_opcode) intersect {7'b0100011} &&
                             binsof(cp_funct3) intersect {3'b111};
      
      ignore_bins branch_f2 = binsof(cp_opcode) intersect {7'b1100011} &&
                              binsof(cp_funct3) intersect {3'b010};
      ignore_bins branch_f3 = binsof(cp_opcode) intersect {7'b1100011} &&
                              binsof(cp_funct3) intersect {3'b011};
      
      ignore_bins jalr_f1 = binsof(cp_opcode) intersect {7'b1100111} &&
                            binsof(cp_funct3) intersect {3'b001};
      ignore_bins jalr_f2 = binsof(cp_opcode) intersect {7'b1100111} &&
                            binsof(cp_funct3) intersect {3'b010};
      ignore_bins jalr_f3 = binsof(cp_opcode) intersect {7'b1100111} &&
                            binsof(cp_funct3) intersect {3'b011};
      ignore_bins jalr_f4 = binsof(cp_opcode) intersect {7'b1100111} &&
                            binsof(cp_funct3) intersect {3'b100};
      ignore_bins jalr_f5 = binsof(cp_opcode) intersect {7'b1100111} &&
                            binsof(cp_funct3) intersect {3'b101};
      ignore_bins jalr_f6 = binsof(cp_opcode) intersect {7'b1100111} &&
                            binsof(cp_funct3) intersect {3'b110};
      ignore_bins jalr_f7 = binsof(cp_opcode) intersect {7'b1100111} &&
                            binsof(cp_funct3) intersect {3'b111};
    }
  endgroup
  
  covergroup cov_decode();
    
    option.per_instance = 1;
    
    cp_funct3 : coverpoint funct3 iff (opcode == 7'b0110011) {
      bins ADD_SUB = {3'b000};
      bins SLL     = {3'b001};
      bins SLT 	   = {3'b010};
      bins SLTU    = {3'b011};
      bins XOR 	   = {3'b100};
      bins SR 	   = {3'b101};
      bins OR 	   = {3'b110};
      bins AND 	   = {3'b111};
    }
    cp_funct7 : coverpoint funct7 iff (opcode == 7'b0110011) {
      bins base = {7'b0000000};
      bins alt  = {7'b0100000};
    }
    
    cross_f3_f7 : cross cp_funct3, cp_funct7 {
      ignore_bins sll_alt  = binsof(cp_funct3) intersect {3'b001} &&
                             binsof(cp_funct7) intersect {7'b0100000};
      ignore_bins slt_alt  = binsof(cp_funct3) intersect {3'b010} &&
                             binsof(cp_funct7) intersect {7'b0100000};
      ignore_bins sltu_alt = binsof(cp_funct3) intersect {3'b011} &&
                             binsof(cp_funct7) intersect {7'b0100000};
      ignore_bins xor_alt  = binsof(cp_funct3) intersect {3'b100} &&
                             binsof(cp_funct7) intersect {7'b0100000};
      ignore_bins or_alt   = binsof(cp_funct3) intersect {3'b110} &&
                             binsof(cp_funct7) intersect {7'b0100000};
      ignore_bins and_alt  = binsof(cp_funct3) intersect {3'b111} &&
                             binsof(cp_funct7) intersect {7'b0100000};
    }
  endgroup
  
  covergroup cov_registers();
    
    option.per_instance = 1;
    
    cp_rs1 : coverpoint rs1 {
      bins zero = {0};
      bins low  = {[1:5]};
      bins mid  = {[6:20]};
      bins high = {[21:31]};
    }
    
    cp_rs2 : coverpoint rs2 {
      bins zero = {0};
      bins low  = {[1:5]};
      bins mid  = {[6:20]};
      bins high = {[21:31]};
    }
    
    cp_rd : coverpoint rd {
      bins zero = {0};
      bins low  = {[1:5]};
      bins mid  = {[6:20]};
      bins high = {[21:31]};
    }
    
    cross_rs1_rd : cross cp_rs1, cp_rd;
    cross_rs2_rd : cross cp_rs2, cp_rd;
  endgroup
  
  covergroup cov_imm();
    
    option.per_instance = 1;
    
    cp_imm : coverpoint imm {
      bins zero = {0};
      bins small_pos = {[1:16]};
      bins mid_pos   = {[17:1023]};
      bins large_pos = {[1024:2047]};
      ignore_bins small_neg = {[-16:-1]};
      bins mid_neg   = {[-1023:-17]};
      bins large_neg = {[-2048:-1024]};
    }
  endgroup
  
  covergroup cov_branch();
    
    option.per_instance = 1;
    
    cp_branch : coverpoint funct3 iff (opcode == 7'b1100011) {
      bins BEQ  = {3'b000};
      bins BNE  = {3'b001};
      bins BLT  = {3'b100};
      bins BGE  = {3'b101};
      bins BLTU = {3'b110};
      bins BGEU = {3'b111};
    }
  endgroup
  
  covergroup cov_forward();
    
    option.per_instance = 1;
    
    cp_forward_a : coverpoint forward_a {
      bins normal = {2'b00};
      bins mem    = {2'b01};
      bins ex     = {2'b10};
    }
    
    cp_forward_b : coverpoint forward_b {
      bins normal = {2'b00};
      bins mem    = {2'b01};
      bins ex     = {2'b10};
    }
    
    cross_ab : cross cp_forward_a, cp_forward_b {
      ignore_bins rare_ex_mem = binsof(cp_forward_a) intersect {2'b10} &&
                                binsof(cp_forward_b) intersect {2'b01};
      ignore_bins rare_mem_ex = binsof(cp_forward_a) intersect {2'b01} &&
                                binsof(cp_forward_b) intersect {2'b10};
    }
  endgroup
  
  covergroup cov_hazard();
    
    option.per_instance = 1;
    
    cp_stall : coverpoint stall_if {
      bins no_stall = {0};
      bins stall = {1};
    }
    
    cp_flush : coverpoint flush_ex {
      bins no_flush = {0};
      bins flush = {1};
    }
    
    cross_stall_flush : cross cp_stall, cp_flush {
      ignore_bins impossible_no_stall_flush =
      binsof(cp_stall) intersect {0} &&
      binsof(cp_flush) intersect {1};
      
      ignore_bins impossible_stall_no_flush = 
      binsof(cp_stall) intersect {1} &&
      binsof(cp_flush) intersect {0};
    }
  endgroup
  
  covergroup cov_redirect();
    
    option.per_instance = 1;
    
    cp_redirect : coverpoint redirect_valid {
      bins no_redirect = {0};
      bins redirect = {1};
    }
  endgroup
  
  covergroup cov_branch_outcome();
    option.per_instance = 1;
    
    cp_branch_funct3 : coverpoint funct3 iff (opcode == 7'b1100011) {
      bins BEQ  = {3'b000};
      bins BNE  = {3'b001};
      bins BLT  = {3'b100};
      bins BGE  = {3'b101};
      bins BLTU = {3'b110};
      bins BGEU = {3'b111};
    }
    
    cp_taken : coverpoint redirect_valid iff (opcode == 7'b1100011) {
      bins not_taken = {0};
      bins taken = {1};
    }
    
    branch_outcome_cross : cross cp_branch_funct3, cp_taken;
  endgroup
  
  covergroup cov_hazard_source();
    option.per_instance = 1;
    
    cp_stall_opocde : coverpoint opcode iff (stall_if) {
      bins load_caused = {7'b0000011};
    }
    
    cp_fwd_a_opcode : coverpoint opcode iff (forward_a != 2'b00) {
      bins r_type = {7'b0110011};
      bins i_type = {7'b0010011};
      bins lui     = {7'b0110111};
      bins auipc   = {7'b0010111};
    }
    
    cp_fwd_b_opcode : coverpoint opcode iff (forward_b != 2'b00) {
      bins r_type = {7'b0110011};
      bins i_type = {7'b0010011};
      bins load    = {7'b0000011};
      bins auipc   = {7'b0010111};
      bins jal     = {7'b1101111};
    }
  endgroup
      
  covergroup cov_reg_hazard();
    option.per_instance = 1;
    
    cp_rd_eq_rs1 : coverpoint (rd == rs1 && rd != 0) iff 
    (opcode inside {7'b0110011, 7'b0010011}) {
      bins no_match = {0};
      bins match = {1};
    }
    
    cp_rd_eq_rs2 : coverpoint (rd == rs2 && rd != 0) iff
    (opcode == 7'b0110011) {
      bins no_match = {0};
      bins match = {1};
    }
    
    cp_rs1_eq_rs2 : coverpoint (rs1 == rs2 && rs1 != 0) iff
    (opcode == 7'b0110011) {
      bins no_match = {0};
      bins match = {1};
    }
  endgroup
  
  covergroup cov_instr_sequence();
    option.per_instance = 1;
    
    cp_prev_type : coverpoint prev_opcode iff (prev_valid) {
      bins r_type  = {7'b0110011};
      bins i_type  = {7'b0010011};
      bins load    = {7'b0000011};
      bins store   = {7'b0100011};
      bins branch  = {7'b1100011};
      bins jal     = {7'b1101111};
      bins lui     = {7'b0110111};
    }
    
    cp_curr_type : coverpoint opcode iff (prev_valid) {
      bins r_type  = {7'b0110011};
      bins i_type  = {7'b0010011};
      bins load    = {7'b0000011};
      bins store   = {7'b0100011};
      bins branch  = {7'b1100011};
      bins jal     = {7'b1101111};
      bins lui     = {7'b0110111};
    }
    
    seq_cross : cross cp_prev_type, cp_curr_type;
  endgroup
  
  covergroup cov_data_dep();
    option.per_instance = 1;
    
    cp_raw_rs1 : coverpoint (prev_rd == rs1 && prev_rd != 0) iff (prev_valid) {
      bins no_dep = {0};
      bins dep = {1};
    }
    
    cp_raw_rs2 : coverpoint (prev_rd == rs2 && prev_rd != 0) iff (prev_valid) {
      bins no_dep = {0};
      bins dep = {1};
    }
      
      cp_raw_both : coverpoint (prev_rd == rs1 && prev_rd == rs2 && prev_rd != 0)
      iff(prev_valid) {
        bins no_dep = {0};
        bins dep = {1};
      }
  endgroup
      
  covergroup cov_corner();
    option.per_instance = 1;
    
    cp_rd_zero : coverpoint (rd == 5'd0) iff
    (opcode inside {7'b0110011, 7'b0110111}) {
      bins non_zerp = {0};
      bins rd_zero = {1};
    }
    
    cp_redirect_after_stall : coverpoint (redirect_valid && stall_if) {
      bins no = {0};
      ignore_bins impossible = {1};
    }
    
    cp_branch_with_fwd : coverpoint (forward_a != 2'b00 || forward_b != 2'b00)
    iff(opcode == 7'b1100011) {
      bins no_fwd = {0};
      bins has_fwd = {1};
    }
  endgroup
  
  covergroup cov_memory();
    option.per_instance = 1;
    
    cp_load_addr : coverpoint imm iff (opcode == 7'b0000011) {
      bins low_addr = {[0:255]};
      bins mid_addr = {[256:1023]};
      bins high_addr = {[1024:4092]};
    }
    
    cp_store_addr : coverpoint imm iff (opcode == 7'b0100011) {
      bins low_addr = {[0:255]};
      bins mid_addr = {[256:1023]};
      bins high_addr = {[1024:4092]};
    }
    
    cp_store_then_load : coverpoint (prev_was_store && opcode == 7'b0000011) {
      bins no = {0};
      bins yes = {1};
    }
  endgroup
      
  covergroup cov_alu_result();
    option.per_instance = 1;
    
    cp_shamt : coverpoint rs2[4:0] iff 
    (opcode == 7'b0110011 && funct3 inside {3'b001, 3'b101}) {
      bins zero = {0};
      bins low = {[1:7]};
      bins mid = {[8:23]};
      bins high = {[24:30]};
      bins max = {31};
    }
    
    cp_shamt_imm : coverpoint imm[4:0] iff
    (opcode == 7'b0010011 && funct3 inside {3'b001, 3'b101}) {
      bins zero = {0};
      bins low = {[1:7]};
      bins mid = {[8:23]};
      bins high = {[24:31]};
    }
    
    cp_slt_result : coverpoint rd iff 
    (opcode == 7'b0110011 && funct3 inside {3'b010, 3'b011}) {
      bins low = {[1:8]};
      bins mid = {[9:20]};
      bins high = {[21:31]};
    }
  endgroup
      
  covergroup cov_branch_direction();
    option.per_instance = 1;
    
    cp_direction : coverpoint imm[31] iff (opcode == 7'b1100011) {
      bins forward = {0};
      bins backward = {1};
    }
    
    cp_taken_dir : coverpoint redirect_valid iff (opcode == 7'b1100011) {
      bins not_taken = {0};
      bins taken = {1};
    }
    
    direction_outcome : cross cp_direction, cp_taken_dir;
  endgroup
      
  covergroup cov_flush_source();
    option.per_instance = 1;
    
    cp_redirect_source : coverpoint opcode iff (redirect_valid) {
      bins branch = {7'b1100011};
      bins jal = {7'b1101111};
      bins jalr = {7'b1100111};
    }
  endgroup
      
  covergroup cov_writeback();
    option.per_instance = 1;
    
    cp_wb_source : coverpoint opcode iff (rd != 0) {
      bins alu_wb[] = {7'b0110011, 7'b0010011, 7'b0110111,
                       7'b0010111, 7'b1101111, 7'b1100111};
      bins mem_wb = {7'b0000011};
    }
  endgroup
  
  function new(input string path = "riscv_coverage", uvm_component parent);
    super.new(path, parent);
    
    cov_recv = new("cov_recv", this);
    cov_opcode = new();
    cov_decode = new();
    cov_registers = new();
    cov_imm = new();
    cov_branch = new();
    cov_forward = new();
    cov_hazard = new();
    cov_redirect = new();
    cov_branch_outcome = new();
    cov_hazard_source = new();
    cov_reg_hazard = new();
    cov_instr_sequence = new();
    cov_data_dep = new();
    cov_corner = new();
    cov_memory = new();
    cov_alu_result = new();
    cov_branch_direction = new();
    cov_flush_source = new();
    cov_writeback = new();
    
  endfunction
  
  virtual function void write(commit_tr ct);
    instr = ct.instr;
    
    if(instr == 32'h00100073) return;
    
    forward_a = ct.forward_a;
    forward_b = ct.forward_b;
    stall_if = ct.stall_if;
    flush_ex = ct.flush_ex;
    redirect_valid = ct.redirect_valid;
    
    opcode = instr[6:0];
    rd = instr[11:7];
    funct3 = instr[14:12];
    rs1 = instr[19:15];
    rs2 = instr[24:20];
    funct7 = instr[31:25];
    
    if(ct.valid) begin
      prev_was_store = (opcode == 7'b0100011);
      prev_imm = imm;
      prev_opcode = opcode;
      prev_rd = rd;
      prev_valid = 1;
      prev_funct3 = funct3;
    end
    
    case(opcode)
      7'b0010011,
      7'b0000011,
      7'b1100111:
        imm = {{20{instr[31]}}, instr[31:20]};
      
      7'b0100011:
        imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
      
      7'b1100011: 
        imm = {{19{instr[31]}},
               instr[31],
               instr[7],
               instr[30:25],
               instr[11:8],
               1'b0};
      
      7'b1101111:
        imm = {{11{instr[31]}},
               instr[31],
               instr[19:12],
               instr[20],
               instr[30:21],
               1'b0};
      
      7'b0110111,
      7'b0010111:
        imm = {instr[31:12], 12'b0};
      
      default: imm = 0;
    endcase
    
    cov_opcode.sample();
    cov_decode.sample();
    cov_registers.sample();
    cov_imm.sample();
    cov_branch.sample();
    cov_forward.sample();
    cov_hazard.sample();
    cov_redirect.sample();
    cov_branch_outcome.sample();
    cov_hazard_source.sample();
    cov_reg_hazard.sample();
    cov_instr_sequence.sample();
    cov_data_dep.sample();
    cov_corner.sample();
    cov_memory.sample();
    cov_alu_result.sample();
    cov_branch_direction.sample();
    cov_flush_source.sample();
    cov_writeback.sample();
    
  endfunction
  
endclass
    
//IMEM Agent
class imem_agent extends uvm_agent;
  `uvm_component_utils(imem_agent)
  
  imem_driver idrv;
  riscv_sequencer seqr;
  
  function new(input string path = "imem_agent", uvm_component parent);
    super.new(path, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(is_active == UVM_ACTIVE) begin
      idrv = imem_driver::type_id::create("idrv", this);
      seqr = riscv_sequencer::type_id::create("seqr", this);
    end
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if(is_active == UVM_ACTIVE) begin
      idrv.seq_item_port.connect(seqr.seq_item_export);
    end
  endfunction
endclass
    
//DMEM Agent
class dmem_agent extends uvm_agent;
  `uvm_component_utils(dmem_agent)
  
  dmem_driver ddrv;
  
  function new(input string path = "dmem_agent", uvm_component parent);
    super.new(path, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(is_active == UVM_ACTIVE) begin
      ddrv = dmem_driver::type_id::create("ddrv", this);
    end
    
  endfunction
endclass
    
//Env
class riscv_env extends uvm_env;
  `uvm_component_utils(riscv_env)
  
  imem_agent ia;
  dmem_agent da;
  riscv_monitor m;
  riscv_scoreboard s;
  riscv_coverage c;
  riscv_exec_monitor em;
  
  function new(input string path = "riscv_env", uvm_component parent);
    super.new(path, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    ia = imem_agent::type_id::create("ia", this);
    da = dmem_agent::type_id::create("da", this);
    ia.is_active = UVM_ACTIVE;
    da.is_active = UVM_ACTIVE;
    m = riscv_monitor::type_id::create("m", this);
    s = riscv_scoreboard::type_id::create("s", this);
    c = riscv_coverage::type_id::create("c", this);
    em = riscv_exec_monitor::type_id::create("em", this);
    
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    m.send.connect(s.recv_c);
    m.send.connect(c.cov_recv);
    em.send_exec.connect(c.cov_recv);
  endfunction
endclass
    
//Test
class riscv_test extends uvm_test;
  `uvm_component_utils(riscv_test)
  
  riscv_env e;
  virtual commit_if cif;
  
  int unsigned num_trans = 200;
  bit use_fixed_type = 0;
  riscv_transaction::instr_types fixed_type;
  
  int unsigned watchdog_multiplier = 30;
  
  function new(input string path = "riscv_test", uvm_component parent);
    super.new(path, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    e = riscv_env::type_id::create("e", this);
    if(!uvm_config_db#(virtual commit_if)::get(this, "", "cif", cif))
      `uvm_error("TEST", "Cannot get commit_if")
  endfunction
  
  task reset_dut();
    cif.rst_drive = 0;
    repeat(3) @(posedge cif.clk);
    cif.rst_drive = 1;
    repeat(2) @(posedge cif.clk);
  endtask
      
    task run_seq(
      input string name,
      input int unsigned n,
      input bit fixed = 0,
      input riscv_transaction::instr_types ftype = riscv_transaction::R_TYPE,
      input bit dep_mode = 0,
      input bit lu_stress = 0,
      input bit warmup = 0
    );
      
      riscv_sequence seq;
      
      cif.rst_drive = 0;
      @(posedge cif.clk);
      
      //reset_dut();
      e.ia.idrv.reset();
      e.da.ddrv.reset();
      e.s.reset_state();
      
      if(warmup) begin
        riscv_sequence warmup_seq;
        warmup_seq = riscv_sequence::type_id::create({name, "_warmup"});
        warmup_seq.num_trans = 32;
        warmup_seq.use_fixed_type = 1;
        warmup_seq.fixed_type = riscv_transaction::LUI_TYPE;
        warmup_seq.start(e.ia.seqr);
      end
      
      seq = riscv_sequence::type_id::create(name);
      seq.num_trans = n;
      seq.use_fixed_type = fixed;
      seq.fixed_type = ftype;
      seq.dependency_mode = dep_mode;
      seq.load_use_stress = lu_stress;
      seq.base_addr = e.ia.idrv.load_addr * 4;
     
      seq.start(e.ia.seqr);
      
      repeat(3) @(posedge cif.clk);
      cif.rst_drive = 1;
      repeat(2) @(posedge cif.clk);
      
      fork : completion_fork
        begin : wait_ebreak
          @(e.m.program_done);
        end
        begin : watchdog
          repeat((n +(warmup ? 32 : 0))* watchdog_multiplier) @(posedge cif.clk);
          `uvm_fatal("TEST", $sformatf(
            "Watchdog: Phase '%s' did not complete in %0d cycle", 
            name, (n+(warmup ? 32 : 0)) *watchdog_multiplier))
        end
      join_any
      disable completion_fork;
    endtask
    
  task run_phase(uvm_phase phase);
    `uvm_info("TEST", "Run phase started", UVM_NONE)
    phase.raise_objection(this);
    
    run_seq("seq_main", num_trans, .fixed(use_fixed_type), .ftype(fixed_type), .warmup(!use_fixed_type));
    
    phase.drop_objection(this);
    
  endtask
endclass
    
//Random Test
class riscv_random_test extends riscv_test;
  `uvm_component_utils(riscv_random_test)
  
  function new(input string path = "riscv_random_test", uvm_component parent);
    super.new(path, parent);
  endfunction
  
  task run_phase(uvm_phase phase);
    
    phase.raise_objection(this);
    
    run_seq("seq_init", 32, .fixed(1), .ftype(riscv_transaction::LUI_TYPE));
    
    run_seq("seq_dep", 300, .dep_mode(1), .warmup(1));
    
    run_seq("seq_rand", 300, .warmup(1));
    
    run_seq("seq_load_stress", 200, .lu_stress(1), .warmup(1));
    
    run_seq("seq_load_full", 100, .fixed(1), .ftype(riscv_transaction::LOAD_TYPE));
    
    run_seq("seq_store_full", 100, .fixed(1), .ftype(riscv_transaction::STORE_TYPE));
    
    run_seq("seq_jalr_full", 100, .fixed(1), .ftype(riscv_transaction::JALR_TYPE));
   
    run_seq("seq_itype_neg", 100, .fixed(1), .ftype(riscv_transaction::I_TYPE));
    
    run_seq("seq_fwd_stress", 300, .dep_mode(1), .warmup(1));
    
    run_seq("seq_fwd_cross", 400, .dep_mode(1), .warmup(1));
    
    phase.drop_objection(this);
  endtask
  
endclass
      
//R-Type Test
class riscv_rtype_test extends riscv_test;                  
  `uvm_component_utils(riscv_rtype_test)
  
  function new(input string path = "riscv_rtype_test", uvm_component parent);
    super.new(path, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    use_fixed_type = 1;
    fixed_type = riscv_transaction::R_TYPE;
    num_trans = 20;
  endfunction

endclass
                            
//I-Type Test
class riscv_itype_test extends riscv_test;                  
  `uvm_component_utils(riscv_itype_test)
  
  function new(input string path = "riscv_itype_test", uvm_component parent);
    super.new(path, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    use_fixed_type = 1;
    fixed_type = riscv_transaction::I_TYPE;
    num_trans = 20;
  endfunction

endclass
                            
//Load test
class riscv_load_test extends riscv_test;
  `uvm_component_utils(riscv_load_test)
  
  function new(input string path = "riscv_load_test", uvm_component parent);
    super.new(path, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    use_fixed_type = 1;
    fixed_type = riscv_transaction::LOAD_TYPE;
    num_trans = 20;
  endfunction

endclass
                            
//Store test
class riscv_store_test extends riscv_test;
  `uvm_component_utils(riscv_store_test)
  
  function new(input string path = "riscv_store_test", uvm_component parent);
    super.new(path, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    use_fixed_type = 1;
    fixed_type = riscv_transaction::STORE_TYPE;
    num_trans = 20;
  endfunction

endclass
                            
//Branch Test
class riscv_branch_test extends riscv_test;
  `uvm_component_utils(riscv_branch_test)
  
  function new(input string path = "riscv_branch_test", uvm_component parent);
    super.new(path, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    use_fixed_type = 1;
    fixed_type = riscv_transaction::BRANCH_TYPE;
    num_trans = 20;
  endfunction
  
endclass
                            
//JAL test
class riscv_jal_test extends riscv_test;
  `uvm_component_utils(riscv_jal_test)
  
  function new(input string path = "riscv_jal_test", uvm_component parent);
    super.new(path, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    use_fixed_type = 1;
    fixed_type = riscv_transaction::JAL_TYPE;
    num_trans = 20;
  endfunction

endclass
                            
//JALR test
class riscv_jalr_test extends riscv_test;
  `uvm_component_utils(riscv_jalr_test)
  
  function new(input string path = "riscv_jalr_test", uvm_component parent);
    super.new(path, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    use_fixed_type = 1;
    fixed_type = riscv_transaction::JALR_TYPE;
    num_trans = 20;
  endfunction

endclass
                            
//LUI test
class riscv_lui_test extends riscv_test;
  `uvm_component_utils(riscv_lui_test)
  
  function new(input string path = "riscv_lui_test", uvm_component parent);
    super.new(path, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    use_fixed_type = 1;
    fixed_type = riscv_transaction::LUI_TYPE;
    num_trans = 20;
  endfunction

endclass
                            
//AUIPC test
class riscv_auipc_test extends riscv_test;
  `uvm_component_utils(riscv_auipc_test)
  
  function new(input string path = "riscv_auipc_test", uvm_component parent);
    super.new(path, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    use_fixed_type = 1;
    fixed_type = riscv_transaction::AUIPC_TYPE;
    num_trans = 20;
  endfunction

endclass
 
//Main
module riscv_tb;
  
  logic clk = 0;
  logic rst_n;
  
  imem_if vif(.clk(clk));
  dmem_if dif(.clk(clk));
  commit_if cif(.clk(clk));
  exec_if eif(.clk(clk));
  
  assign rst_n = cif.rst_drive;
  
  riscv_core dut(
    .clk(clk),
    .rst_n(rst_n),
    .imem(vif),
    .dmem(dif),
    .commit(cif)
  );
  
  always #5 clk = ~clk;
  
  initial begin
    cif.rst_drive = 0;
    repeat(5) @(posedge clk);
    cif.rst_drive = 1;
  end
  
  initial begin

    uvm_config_db#(virtual imem_if)::set(null, "*", "vif", vif);

    uvm_config_db#(virtual dmem_if)::set(null, "*", "dif", dif);

    uvm_config_db#(virtual commit_if)::set(null, "*", "cif", cif);
    
    uvm_config_db#(virtual exec_if)::set(null, "*", "eif", eif);

    run_test();

  end

  /*
  initial begin
    $dumpfile("dump.vcd"); 
    $dumpvars();
  end*/
  
endmodule
