-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2022 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): jmeno <login AT stud.fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

    signal pc_reg : std_logic_vector(12 downto 0); -- 16 bitu, resp. 0x1000 v hex
    signal pc_inc : std_logic;
    signal pc_dec : std_logic;

    signal ptr_reg : std_logic_vector(12 downto 0); 
    signal ptr_inc : std_logic;
    signal ptr_dec : std_logic;

    signal ct_reg : std_logic_vector(7 downto 0);
    signal ct_inc : std_logic;
    signal ct_dec : std_logic;

    signal mx_sel : std_logic;--_vector(1 downto 0); 
    signal mx_2_sel : std_logic_vector(1 downto 0);  

    type fsm_state is (
        state_start,
        s_fetch,
        s_decode,
        s_other,
        s_stop,

        s_val_inc,
        s_val_inc2,
        s_val_dec,
        s_val_dec2,

        s_ptr_inc,
        s_ptr_dec,

        s_while,
        s_while_2,
        s_while_3,
        s_while_4,
        s_while_e,
        s_while_e2,
        s_while_e3,
        s_while_e4, 
        s_while_e5,
        s_while_e6,

        s_do,
        s_do_2,
        s_do_3,
        s_do_4,
        s_do_5,
        s_do_6,
        s_do_e,
        s_do_e2,
        s_do_e3,
        s_do_e4,
        s_do_e5,
        s_do_e6,

        s_write,
        s_write_n,
        s_get,
        s_get_n
    );

    signal p_state : fsm_state := state_start;
    signal n_state : fsm_state;

begin

     
    ptr_process: process (RESET, CLK) is
    begin
        IF (RESET = '1') THEN
			ptr_reg <= "1000000000000";
		ELSIF (rising_edge(CLK)) THEN
			IF (ptr_inc = '1') THEN
				IF ptr_reg = "1111111111111" THEN
					ptr_reg <= "1000000000000";
				ELSE
					ptr_reg <= ptr_reg + 1;
				END IF;
			ELSIF (ptr_dec = '1') THEN
				IF ptr_reg = "1000000000000" THEN
					ptr_reg <= "1111111111111";
				ELSE
					ptr_reg <= ptr_reg - 1;
				END IF;
			END IF;
		END IF;
	END PROCESS;
--------------------------------------------------------------------------------------------------------------
    pc_process: process (RESET, CLK) is
    begin
        if RESET = '1' then
            pc_reg <= "0000000000000";
        elsif rising_edge(CLK) then
            if pc_inc = '1' then
                pc_reg <= pc_reg + 1;
            elsif pc_dec = '1' then
                pc_reg <= pc_reg - 1;
            end if;
        end if;
    end process;
--------------------------------------------------------------------------------------------------------------
    ct_cnt : PROCESS (CLK, RESET) IS
	BEGIN
		IF (RESET = '1') THEN
			ct_reg <= (OTHERS => '0');
		ELSIF (rising_edge(CLK)) THEN
			IF (ct_inc = '1') THEN
				ct_reg <= ct_reg + 1;
			ELSIF (ct_dec = '1') THEN
				ct_reg <= ct_reg - 1;
			END IF;
		END IF;
	END PROCESS;
--------------------------------------------------------------------------------------------------------------
    mx_1_logic : PROCESS (mx_sel, pc_reg, ptr_reg)
	BEGIN
		IF (mx_sel = '0') THEN
			DATA_ADDR <= pc_reg;
		ELSE
			DATA_ADDR <= ptr_reg;
		END IF;
	END PROCESS;
--------------------------------------------------------------------------------------------------------------
    mx_2_logic: process (RESET, CLK, mx_2_sel, IN_DATA, DATA_RDATA) is
    begin 
            case mx_2_sel is
                when "00" => DATA_WDATA <= IN_DATA;
                when "01" => DATA_WDATA <= DATA_RDATA + 1;
                when "10" => DATA_WDATA <= DATA_RDATA - 1;
                when others => NULL;
            end case;
    end process;
--------------------------------------------------------------------------------------------------------------
    c_state_fsm: process (RESET, CLK, EN) is
    begin
		if RESET = '1' then
			p_state <= state_start;
        elsif rising_edge(CLK) then
			if EN = '1' then
				p_state <= n_state;
        	end if;
        end if;
    end process;
--------------------------------------------------------------------------------------------------------------
	n_state_fsm: process (p_state, DATA_RDATA, IN_VLD, IN_DATA, OUT_BUSY) is
	begin
		pc_inc <= '0';
		pc_dec <= '0';
		ptr_inc <= '0';
		ptr_dec <= '0';
    ct_inc <= '0';
    ct_dec <= '0';
    mx_sel <= '1';
    mx_2_sel <= "00";
		IN_REQ <= '0';
		DATA_EN <= '0';
		DATA_RDWR <= '0';
		OUT_WE <= '0';
    OUT_DATA <= DATA_RDATA;

		case p_state is
			when state_start =>
				n_state <= s_fetch;
	------------------------------------
			when s_fetch =>
        DATA_RDWR <= '0';
        mx_sel <= '0';
        DATA_EN <= '1';
				n_state <= s_decode;
	------------------------------------
			when s_decode =>
				case DATA_RDATA is
        when X"00" => n_state <= s_stop;
					when X"3E" =>
						n_state <= s_ptr_inc;
					when X"3C" =>
						n_state <= s_ptr_dec;
					when X"2B" =>
						n_state <= s_val_inc;
					when X"2D" =>
						n_state <= s_val_dec;
          when X"5B" =>
						n_state <= s_while; 
					when X"5D" =>
						n_state <= s_while_e;
          when X"28" => 
            n_state <= s_do; 
          when X"29" => 
            n_state <= s_do_e; 
					when X"2E" =>
						n_state <= s_write; 
					when X"2C" =>
						n_state <= s_get; 
					when others =>
						n_state <= s_other;
				end case;
--------------------------------------------------------------------------------------------------------------
        when s_ptr_inc => 
            ptr_inc <= '1';
            pc_inc <= '1';
            n_state <= s_fetch;
        when s_ptr_dec =>
            ptr_dec <= '1';
            pc_inc <= '1';
            n_state <= s_fetch;
    ----------------------------------------
        when s_val_inc =>
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            n_state <= s_val_inc2;
        when s_val_inc2 =>
            DATA_EN <= '1';
            DATA_RDWR <= '1';
            mx_sel <= '1';
            mx_2_sel <= "01";
            pc_inc <= '1';
            n_state <= s_fetch;
    ----------------------------------------
        when s_val_dec =>
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            n_state <= s_val_dec2;
        when s_val_dec2 =>
            DATA_EN <= '1';
            DATA_RDWR <= '1';
            mx_sel <= '1';
            mx_2_sel <= "10";
            pc_inc <= '1';
            n_state <= s_fetch;
    
--------------------------------------------------------------------------------------------------------------
      WHEN s_write =>
				DATA_EN <= '1';
				DATA_RDWR <= '0';
				n_state <= s_write_n;

			WHEN s_write_n =>
				mx_sel <= '1';
				IF OUT_BUSY = '0' THEN
					OUT_WE <= '1';
					OUT_DATA <= DATA_RDATA;
					pc_inc <= '1';
					n_state <= s_fetch;
				ELSE
					n_state <= s_write;
				END IF;

			WHEN s_get =>
				DATA_EN <= '1';
				IN_REQ <= '1';
				DATA_RDWR <= '0';
				mx_sel <= '1';
				n_state <= s_get_n;

			WHEN s_get_n =>
				IF IN_VLD = '1' THEN
					mx_2_sel <= "00";
					DATA_EN <= '1';
					DATA_RDWR <= '1';
					pc_inc <= '1';
					n_state <= s_fetch;
				ELSE
					n_state <= s_get;
				END IF;
------------------------------------------------------------------------------------ [WHILE
            when s_while =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                pc_inc <= '1';
                n_state <= s_while_2;  
            when s_while_2 =>
                if DATA_RDATA = X"00" then
                    ct_inc <= '1';
                    n_state <= s_while_3;
                else
                    n_state <= s_fetch;
                end if;
            when s_while_3 =>
                if ct_reg = X"00" then
                    --DATA_EN <= '1';
                    n_state <= s_fetch;
                else
                    DATA_EN <= '1';
                    mx_sel <= '0';
                    DATA_RDWR <= '0';
                    n_state <= s_while_4;
                end if ;
            when s_while_4 =>
                if DATA_RDATA = X"5D" then
                    ct_dec <= '1';
                elsif DATA_RDATA = X"5B" then
                    ct_inc <= '1';
                end if;
                pc_inc <= '1';
                n_state <= s_while_3;
------------------------------------------------------------------------------------ WHILE]
                when s_while_e =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                n_state <= s_while_e2;
            when s_while_e2 =>
                if (DATA_RDATA = X"00") then
                pc_inc <= '1';
                n_state <= s_fetch;
                else
                    ct_inc <='1';
                    pc_dec <= '1';
                n_state <= s_while_e3;
                end if;
            when s_while_e3 =>
                pc_dec <= '1';
                n_state <= s_while_e4;
            when s_while_e4 =>
            if ct_reg = X"00" then
                --DATA_EN <= '1';
                --DATA_RDWR <= '0';
                n_state <= s_fetch;
            else
                DATA_EN <= '1';
                mx_sel <= '0';
                DATA_RDWR <= '0';
                n_state <= s_while_e5;
            end if;
            when s_while_e5 =>
                if DATA_RDATA = X"5D" then
                    ct_inc <= '1';
                elsif DATA_RDATA = X"5B" then
                    ct_dec <= '1';
                end if;
                n_state <= s_while_e6;
            when s_while_e6 =>
                if ct_reg = X"00" then
                    pc_inc <= '1';
                else
                    pc_dec <= '1';
                end if;
                n_state <= s_while_e4;
------------------------------------------------------------------------------------ DO WHILE (
            when s_do =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                mx_sel <= '1';
                n_state <= s_do_2;
            when s_do_2 =>
                pc_inc <= '1';
                n_state <= s_do_3;
            when s_do_3 =>
            if ct_reg = X"00" then
                --DATA_EN <= '1';
                n_state <= s_fetch;
            else
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                mx_sel <= '0';
                n_state <= s_do_4;
            end if;
            when s_do_4 =>
                if DATA_RDATA = X"28" then
                    ct_inc <= '1';
                elsif DATA_RDATA = X"29" then
                    ct_dec <= '1';
                end if;
                n_state <= s_do_5;
            when s_do_5 =>
                if ct_reg = X"00" then
                    pc_inc <= '1';
                else
                    pc_dec <= '1';
                end if;
                n_state <= s_do_3;
------------------------------------------------------------------------------------ DO WHILE )
                when s_do_e =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                pc_inc <= '1';
                mx_sel <= '1';
                n_state <= s_do_e2;  
            when s_do_e2 =>
                    ct_inc <= '1';
                n_state <= s_do_e3;
            when s_do_e3 =>
                if ct_reg = X"00" then
                    --DATA_EN <= '1';
                    n_state <= s_fetch;
                else
                    DATA_EN <= '1';
                    DATA_RDWR <= '0';
                    mx_sel <= '0';
                    n_state <= s_do_e4;
                end if ;
            when s_do_e4 =>
                if DATA_RDATA = X"28" then
                    ct_inc <= '1';
                elsif DATA_RDATA = X"29" then
                    ct_dec <= '1';
                end if;
                pc_dec <= '1';
                n_state <= s_do_e3;
--------------------------------------------------------------------------------------------------------------
      when s_stop => n_state <= s_stop;
-------------------------------------------------------------------------------------------------------------
      when s_other =>
        pc_inc <= '1';
        n_state <= s_fetch;
--------------------------------------------------------------------------------------------------------------
			when others => NULL;
		end case;
	end process;

end behavioral;
