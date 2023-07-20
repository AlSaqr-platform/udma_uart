// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

///////////////////////////////////////////////////////////////////////////////
//
// Description: UART RX module
//
///////////////////////////////////////////////////////////////////////////////
//
// Authors    : Antonio Pullini (pullinia@iis.ee.ethz.ch)
//
///////////////////////////////////////////////////////////////////////////////

module udma_uart_rx (
		input  logic            clk_i,
		input  logic            rstn_i,
		input  logic            rx_i,
		input  logic [15:0]     cfg_div_i,
        input  logic            cfg_en_i,
        input  logic            cfg_parity_en_i,
		input  logic  [1:0]     cfg_bits_i,
		input  logic            cfg_stop_bits_i,
        output logic            busy_o,
        output logic            err_parity_o,
        output logic            err_overflow_o,
        output logic            char_event_o,
		output logic  [7:0]     rx_data_o,
		output logic            rx_valid_o,
		input  logic            rx_ready_i
		//
		//output logic			rts_o,
		//input  logic			rts_en_i
		);
	
	enum logic [2:0] {IDLE,START_BIT,DATA,PARITY,STOP_BIT} CS,NS;
	
	logic [7:0] reg_data;
	logic [7:0] reg_data_next;

    logic [2:0] reg_rx_sync;


	logic [2:0] reg_bit_count;
	logic [2:0] reg_bit_count_next;

	logic [2:0] s_target_bits;
	
	logic       parity_bit;
	logic       parity_bit_next;
	
	logic       s_sample_data;
	
	logic [15:0] baud_cnt;
	logic        baudgen_en;
	logic        bit_done;

    logic        start_bit;
    logic        s_rx_fall;

    logic        s_set_error_parity;
    logic        r_error_parity;
    logic        s_err_clear;

    assign busy_o = (CS != IDLE);
    //
    //assign rts_o = ~rx_ready_i & rts_en_i;
    //

    always_comb
    begin
        case(cfg_bits_i)
            2'b00:
                s_target_bits = 3'h4;
            2'b01:
                s_target_bits = 3'h5;
            2'b10:
                s_target_bits = 3'h6;
            2'b11:
                s_target_bits = 3'h7;
        endcase
    end
	
	always_comb
	begin
		NS = CS;
		s_sample_data = 1'b0;
		reg_bit_count_next  = reg_bit_count;
		reg_data_next = reg_data;
		rx_valid_o = 1'b0;
		baudgen_en = 1'b0;
        start_bit  = 1'b0;
		parity_bit_next = parity_bit;
        err_parity_o    = 1'b0;
        err_overflow_o  = 1'b0;
        char_event_o    = 1'b0;
        s_set_error_parity   = 1'b0;
        s_err_clear          = 1'b0;
		case(CS)
			IDLE:
            begin
				if (s_rx_fall)
				begin
					NS = START_BIT;
    				baudgen_en = 1'b1;
                    start_bit  = 1'b1;
                    s_err_clear = 1'b1;
				end
            end

			START_BIT:
			begin
				parity_bit_next = 1'b0;
				baudgen_en = 1'b1;
                start_bit  = 1'b1;
				if (bit_done)
					NS = DATA;
			end

			DATA:
			begin
				baudgen_en = 1'b1;
				parity_bit_next = parity_bit ^ reg_rx_sync[2];
                case(cfg_bits_i)
                    2'b00:
                        reg_data_next = {3'b000,reg_rx_sync[2],reg_data[4:1]};
                    2'b01:
                        reg_data_next = {2'b00,reg_rx_sync[2],reg_data[5:1]};
                    2'b10:
                        reg_data_next = {1'b0,reg_rx_sync[2],reg_data[6:1]};
                    2'b11:
                        reg_data_next = {reg_rx_sync[2],reg_data[7:1]};
                endcase
        		
				if (bit_done)
				begin
					s_sample_data = 1'b1;
					if (reg_bit_count == s_target_bits)
					begin
						reg_bit_count_next = 'h0;
						if (cfg_parity_en_i)
							NS = PARITY;
						else
							NS = STOP_BIT;
					end
					else
					begin
						reg_bit_count_next = reg_bit_count + 1;
					end
				end
			end
			PARITY:
			begin
				baudgen_en = 1'b1;
				if (bit_done)
                begin
                    if(parity_bit != reg_rx_sync[2])
                        s_set_error_parity = 1'b1;
				    NS = STOP_BIT;
                end
			end
			STOP_BIT:
			begin
				baudgen_en = 1'b1;
				if (bit_done)
				begin
					NS = IDLE;
					if(!r_error_parity)
					begin
						rx_valid_o = 1'b1;
						if(!rx_ready_i)
							err_overflow_o = 1'b1;
						else
							char_event_o = 1'b1;
					end
					else
						err_parity_o = 1'b1;
				end
			end
            default:
                NS = IDLE;
		endcase		
	end
	
	always_ff @(posedge clk_i or negedge rstn_i)
	begin
		if (rstn_i == 1'b0)
		begin
			CS             <= IDLE;
			reg_data       <= 8'hFF;
			reg_bit_count  <=  'h0;
			parity_bit     <= 1'b0;
		end
		else
		begin
            if(bit_done)
                parity_bit <= parity_bit_next;
			if(s_sample_data)
				reg_data <= reg_data_next;

			reg_bit_count  <= reg_bit_count_next;
            if(cfg_en_i)
	           CS <= NS;
            else
                CS <= IDLE;
		end
	end

    assign s_rx_fall = ~reg_rx_sync[1] & reg_rx_sync[2];
	always_ff @(posedge clk_i or negedge rstn_i)
	begin
		if (rstn_i == 1'b0)
            reg_rx_sync <= 3'b111;
		else
        begin
            if (cfg_en_i)
                reg_rx_sync <= {reg_rx_sync[1:0],rx_i};
            else
                reg_rx_sync <= 3'b111;
        end
    end

	always_ff @(posedge clk_i or negedge rstn_i)
	begin
		if (rstn_i == 1'b0)
		begin
			baud_cnt <= 'h0;
			bit_done <= 1'b0;
		end
		else
		begin
			if(baudgen_en)
			begin
				if(!start_bit && (baud_cnt == cfg_div_i))
				begin
					baud_cnt <= 'h0;
					bit_done <= 1'b1;
				end
				else if(start_bit && (baud_cnt == {1'b0,cfg_div_i[15:1]}))
				begin
					baud_cnt <= 'h0;
					bit_done <= 1'b1;
				end
				else 
				begin
					baud_cnt <= baud_cnt + 1;
					bit_done <= 1'b0;
				end
			end
			else
			begin
				baud_cnt <= 'h0;
				bit_done <= 1'b0;
			end
		end
	end

	always_ff @(posedge clk_i or negedge rstn_i)
	begin
		if (rstn_i == 1'b0)
		begin
			r_error_parity   <= 1'b0;
		end
		else
		begin
			if(s_err_clear)
			begin
				r_error_parity   <= 1'b0;
			end
			else
			begin
                if(s_set_error_parity)
    			    r_error_parity <= 1'b1;
			end
		end
	end

    assign rx_data_o = reg_data;
	
endmodule
