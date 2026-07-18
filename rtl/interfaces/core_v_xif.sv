/*
 Copyright 2024 OpenhW Group
 Copyright 2021 TU Wien
 Copyright 2021 ETH Zurich and University of Bologna

 This file, and derivatives thereof are licensed under the
 Solderpad License, Version 2.0 (the "License");
 Use of this file means you agree to the terms and conditions
 of the License and are in full compliance with the License.
 You may obtain a copy of the License at

 https://solderpad.org/licenses/SHL-2.0/

 Unless required by applicable law or agreed to in writing, software
 and hardware implementations thereof distributed under the License are
 distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either expressed or implied. See the License for the specific language
 governing permissions and limitations under the License.
*/

// Derived from the canonical CV-X-IF SystemVerilog interface at:
// https://github.com/openhwgroup/core-v-xif/blob/main/src/core_v_xif.sv
interface core_v_xif #(
  parameter int unsigned X_NUM_RS               = 2,
  parameter int unsigned X_ID_WIDTH             = 4,
  parameter int unsigned X_RFR_WIDTH            = 32,
  parameter int unsigned X_RFW_WIDTH            = 32,
  parameter int unsigned X_NUM_HARTS            = 1,
  parameter int unsigned X_HARTID_WIDTH         = 1,
  parameter logic [25:0] X_MISA                 = '0,
  parameter int unsigned X_DUALREAD             = 0,
  parameter int unsigned X_DUALWRITE            = 0,
  parameter int unsigned X_ISSUE_REGISTER_SPLIT = 0,
  parameter int unsigned X_MEM_WIDTH            = 32
);

  typedef logic [X_NUM_RS+X_DUALREAD-1:0] readregflags_t;
  typedef logic [X_DUALWRITE:0] writeregflags_t;
  typedef logic [1:0] mode_t;
  typedef logic [X_ID_WIDTH-1:0] id_t;
  typedef logic [X_HARTID_WIDTH-1:0] hartid_t;

  typedef struct packed {
    logic [15:0] instr;
    hartid_t     hartid;
  } x_compressed_req_t;

  typedef struct packed {
    logic [31:0] instr;
    logic        accept;
  } x_compressed_resp_t;

  typedef struct packed {
    logic [31:0] instr;
    mode_t       mode;
    hartid_t     hartid;
    id_t         id;
  } x_issue_req_t;

  typedef struct packed {
    logic           accept;
    writeregflags_t writeback;
    readregflags_t  register_read;
    logic           loadstore;
  } x_issue_resp_t;

  typedef struct packed {
    hartid_t hartid;
    id_t     id;
    // The canonical source uses an unpacked rs array inside this packed
    // structure. Use an equivalent packed array for VCS 2018 compatibility.
    logic [X_NUM_RS-1:0][X_RFR_WIDTH-1:0] rs;
    readregflags_t          rs_valid;
  } x_register_t;

  typedef struct packed {
    hartid_t hartid;
    id_t     id;
    logic    commit_kill;
  } x_commit_t;

  typedef struct packed {
    hartid_t                    hartid;
    id_t                        id;
    logic [31:0]                addr;
    mode_t                      mode;
    logic                       we;
    logic [2:0]                 size;
    logic [X_MEM_WIDTH/8-1:0]   be;
    logic [1:0]                 attr;
    logic [X_MEM_WIDTH-1:0]     wdata;
    logic                       last;
    logic                       spec;
  } x_mem_req_t;

  typedef struct packed {
    logic       exc;
    logic [5:0] exccode;
    logic       dbg;
  } x_mem_resp_t;

  typedef struct packed {
    hartid_t                hartid;
    id_t                    id;
    logic [X_MEM_WIDTH-1:0] rdata;
    logic                   err;
    logic                   dbg;
  } x_mem_result_t;

  typedef struct packed {
    hartid_t                 hartid;
    id_t                     id;
    logic [X_RFW_WIDTH-1:0]  data;
    logic [4:0]              rd;
    writeregflags_t          we;
    logic                    exc;
    logic [5:0]              exccode;
    logic                    dbg;
    logic                    err;
  } x_result_t;

  logic               compressed_valid;
  logic               compressed_ready;
  x_compressed_req_t  compressed_req;
  x_compressed_resp_t compressed_resp;

  logic          issue_valid;
  logic          issue_ready;
  x_issue_req_t  issue_req;
  x_issue_resp_t issue_resp;

  logic        register_valid;
  logic        register_ready;
  x_register_t register;

  logic      commit_valid;
  x_commit_t commit;

  logic        mem_valid;
  logic        mem_ready;
  x_mem_req_t  mem_req;
  x_mem_resp_t mem_resp;

  logic          mem_result_valid;
  x_mem_result_t mem_result;

  logic      result_valid;
  logic      result_ready;
  x_result_t result;

  modport core_v_xif_cpu_compressed (
    output compressed_valid, compressed_req,
    input  compressed_ready, compressed_resp
  );
  modport core_v_xif_cpu_issue (
    output issue_valid, issue_req,
    input  issue_ready, issue_resp
  );
  modport core_v_xif_cpu_register (
    output register_valid, register,
    input  register_ready
  );
  modport core_v_xif_cpu_commit (
    output commit_valid, commit
  );
  modport core_v_xif_cpu_mem (
    input  mem_valid, mem_req,
    output mem_ready, mem_resp
  );
  modport core_v_xif_cpu_mem_result (
    output mem_result_valid, mem_result
  );
  modport core_v_xif_cpu_result (
    input  result_valid, result,
    output result_ready
  );

  modport core_v_xif_coprocessor_compressed (
    input  compressed_valid, compressed_req,
    output compressed_ready, compressed_resp
  );
  modport core_v_xif_coprocessor_issue (
    input  issue_valid, issue_req,
    output issue_ready, issue_resp
  );
  modport core_v_xif_coprocessor_register (
    input  register_valid, register,
    output register_ready
  );
  modport core_v_xif_coprocessor_commit (
    input commit_valid, commit
  );
  modport core_v_xif_coprocessor_mem (
    output mem_valid, mem_req,
    input  mem_ready, mem_resp
  );
  modport core_v_xif_coprocessor_mem_result (
    input mem_result_valid, mem_result
  );
  modport core_v_xif_coprocessor_result (
    output result_valid, result,
    input  result_ready
  );

endinterface : core_v_xif
