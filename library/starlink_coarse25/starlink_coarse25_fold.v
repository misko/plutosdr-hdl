// Exact rational 750 Hz folding of an accepted 2.5 MS/s score stream.
// 10,000 samples = three frames. GROUPS=29 gives 116 ms / 87 frames per map.
// Two RAM banks: fill one while scanning/clearing the other. No RX backpressure.
module starlink_coarse25_fold #(
  parameter integer GROUPS = 29
) (
  input wire clk,
  input wire reset,
  input wire flush,
  input wire score_valid,
  input wire [7:0] score,
  input wire [63:0] score_first_index,
  output wire initializing,
  output reg fault,
  output wire candidate_valid,
  output reg detected,
  output reg [63:0] candidate_map_first_index,
  output reg [13:0] candidate_phase,
  output reg [14:0] candidate_peak,
  output reg [27:0] candidate_background_sum,
  output reg [42:0] candidate_background_sumsq,
  output reg [13:0] candidate_background_count
);
  initial if (GROUPS < 1 || GROUPS > 32) $fatal(1,"GROUPS must be 1..32");
  localparam INIT=0, IDLE=1, PEAK=2, BG_START=3, BACKGROUND=4, DRAIN=5, CLEAR=6;
  (* ram_style="block" *) reg [12:0] memory [0:19999];
  reg [2:0] state;
  reg [14:0] clear_address;
  reg fill_bank, scan_bank;
  reg [1:0] acc_state;
  reg [14:0] acc_address;
  reg [7:0] acc_score;
  reg [12:0] acc_old;
  reg acc_last;
  reg [18:0] count;
  reg [13:0] phase;
  reg have_index;
  reg [63:0] expected_index, tile_first, scan_first;
  reg [13:0] read_position, read_tag;
  reg read_valid;
  reg [12:0] ram_q, previous, current;
  reg [14:0] peak_value;
  reg [13:0] peak_bin;
  reg bg_valid1, bg_valid2;
  reg [14:0] bg_value1, bg_value2;
  (* use_dsp="yes" *) reg [29:0] bg_square2;
  reg [27:0] bg_sum;
  reg [42:0] bg_sumsq;
  reg [13:0] bg_count;
  reg [2:0] drain_count, gate_stage;
  (* use_dsp="yes" *) reg [28:0] peak_count;
  (* use_dsp="yes" *) reg [55:0] sum_squared;
  (* use_dsp="yes" *) reg [56:0] count_sumsq;
  reg [28:0] delta;
  reg [56:0] variance;
  (* use_dsp="yes" *) reg [57:0] delta_squared;
  reg result_pulse;
  wire [13:0] scan_bin = read_tag - 14'd2;
  wire [14:0] folded = {2'b0,previous}+{2'b0,current}+{2'b0,ram_q};
  wire [13:0] distance = scan_bin >= peak_bin ? scan_bin-peak_bin : peak_bin-scan_bin;
  wire in_background = distance > 150 && distance < 9850;
  wire [13:0] read_bin = read_position == 0 ? 14'd9999 :
                              read_position == 10001 ? 14'd0 : read_position-1'b1;
  wire [14:0] scan_address = (scan_bank ? 15'd10000 : 15'd0) + read_bin;
  assign initializing = state == INIT;
  assign candidate_valid = result_pulse && !reset && !flush && !fault;

  always @(posedge clk) begin
    result_pulse <= 0;
    bg_valid1 <= 0;
    bg_valid2 <= bg_valid1;
    if (reset || flush || fault) begin
      state <= INIT;
      clear_address <= 0;
      fill_bank <= 0;
      scan_bank <= 0;
      acc_state <= 0;
      count <= 0;
      phase <= 0;
      have_index <= 0;
      expected_index <= 0;
      tile_first <= 0;
      scan_first <= 0;
      read_position <= 0;
      read_valid <= 0;
      bg_valid1 <= 0;
      bg_valid2 <= 0;
      gate_stage <= 0;
      fault <= 0;
      detected <= 0;
      candidate_map_first_index <= 0;
      candidate_phase <= 0;
      candidate_peak <= 0;
      candidate_background_sum <= 0;
      candidate_background_sumsq <= 0;
      candidate_background_count <= 0;
    end else if (state == INIT) begin
      // A real sequential RAM clear, never a giant reset fanout into RAM bits.
      memory[clear_address] <= 0;
      if (clear_address == 19999) begin
        state <= IDLE;
        clear_address <= 0;
      end else clear_address <= clear_address + 1'b1;
    end else begin
      // RAM port A: one read/modify/write per score, minimum spacing 3 clocks.
      if (score_valid) begin
        if (acc_state != 0 || (have_index && score_first_index != expected_index)) fault <= 1;
        else begin
          have_index <= 1;
          expected_index <= score_first_index + 64'd1;
          if (count == 0) tile_first <= score_first_index;
          acc_address <= (fill_bank ? 15'd10000 : 15'd0) + phase;
          acc_score <= score;
          acc_last <= count == GROUPS*10000-1;
          acc_state <= 1;
          count <= count == GROUPS*10000-1 ? 0 : count + 1'b1;
          phase <= phase >= 9997 ? phase-14'd9997 : phase+14'd3;
        end
      end
      if (acc_state == 1) begin
        acc_old <= memory[acc_address];
        acc_state <= 2;
      end else if (acc_state == 2) begin
        memory[acc_address] <= acc_old + acc_score;
        acc_state <= 0;
        if (acc_last) begin
          if (state != IDLE) fault <= 1;
          else begin
            scan_bank <= fill_bank;
            fill_bank <= !fill_bank;
            scan_first <= tile_first;
            state <= PEAK;
            read_position <= 0;
            read_valid <= 0;
            peak_value <= 0;
            peak_bin <= 0;
          end
        end
      end

      // RAM port B: stream the circular three-bin window through registered reads.
      if (state == PEAK || state == BACKGROUND) begin
        read_valid <= read_position <= 10001;
        if (read_position <= 10001) begin
          ram_q <= memory[scan_address];
          read_tag <= read_position;
          read_position <= read_position + 1'b1;
        end
        if (read_valid) begin
          if (read_tag == 0) previous <= ram_q;
          else if (read_tag == 1) current <= ram_q;
          else begin
            previous <= current;
            current <= ram_q;
            if (state == PEAK) begin
              if (folded > peak_value) begin peak_value <= folded; peak_bin <= scan_bin; end
              if (read_tag == 10001) state <= BG_START;
            end else begin
              bg_valid1 <= in_background;
              bg_value1 <= folded;
              if (read_tag == 10001) begin state <= DRAIN; drain_count <= 3; end
            end
          end
        end
      end else read_valid <= 0;

      if (state == BG_START) begin
        read_position <= 0;
        read_valid <= 0;
        bg_sum <= 0;
        bg_sumsq <= 0;
        bg_count <= 0;
        state <= BACKGROUND;
      end
      if (bg_valid1) begin
        bg_value2 <= bg_value1;
        bg_square2 <= bg_value1 * bg_value1;
      end
      if (bg_valid2) begin
        bg_sum <= bg_sum + bg_value2;
        bg_sumsq <= bg_sumsq + bg_square2;
        bg_count <= bg_count + 1'b1;
      end
      if (state == DRAIN) begin
        if (drain_count == 0) begin state <= CLEAR; clear_address <= 0; gate_stage <= 1; end
        else drain_count <= drain_count - 1'b1;
      end
      if (state == CLEAR) begin
        memory[(scan_bank ? 15'd10000 : 15'd0)+clear_address] <= 0;
        if (clear_address == 9999) state <= IDLE;
        else clear_address <= clear_address + 1'b1;
      end

      // z>=8 without division: (N*peak-sum)^2 >= 64*(N*sumsq-sum^2).
      // Full-width registered products; this happens once per completed map.
      case (gate_stage)
        1: begin
          peak_count <= peak_value * bg_count;
          sum_squared <= bg_sum * bg_sum;
          count_sumsq <= bg_count * bg_sumsq;
          gate_stage <= 2;
        end
        2: begin
          delta <= peak_count >= bg_sum ? peak_count-bg_sum : 0;
          variance <= count_sumsq-{1'b0,sum_squared};
          gate_stage <= 3;
        end
        3: begin delta_squared <= delta * delta; gate_stage <= 4; end
        4: begin
          candidate_map_first_index <= scan_first;
          candidate_phase <= peak_bin;
          candidate_peak <= peak_value;
          candidate_background_sum <= bg_sum;
          candidate_background_sumsq <= bg_sumsq;
          candidate_background_count <= bg_count;
          detected <= bg_count == 9699 && delta != 0 && {5'b0,delta_squared} >= {variance,6'b0};
          result_pulse <= 1;
          gate_stage <= 0;
        end
        default: begin end
      endcase
    end
  end
endmodule
