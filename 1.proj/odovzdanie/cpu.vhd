-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2022 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Frederika Kmetova <xkmeto00@stud.fit.vutbr.cz>
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
  type fsm_state is (
    state_start,
    state_fetch, 
    state_decode,

    state_ptr_inc, 
    state_ptr_dec,

    state_value_inc,
    state_value_inc_next,
    state_value_dec,
    state_value_dec_next,

    state_while_start,
    state_while_next,
    state_while_next2,
    state_while_next3,

    state_while_end,
    state_while_end_next,
    state_while_end_next2,
    state_while_end_next3,
    state_while_end_next4,

    state_do,
    state_do_next,

    state_do_end,
    state_do_end_next,
    state_do_end_next2,
    state_do_end_next3,
    state_do_end_next4,
    state_do_end_next5,

    state_write, -- .
    state_write_next,
    state_read,  -- ,
    state_read_next,
    state_stop,
    state_ignore
  );
  signal stateS : fsm_state; -- state_start
  signal stateN : fsm_state; -- state_next

  --pc
  signal pc_reg : std_logic_vector(12 downto 0); 
  signal pc_inc : std_logic;
  signal pc_dec : std_logic;

  --ptr
  signal ptr_reg : std_logic_vector(12 downto 0);
  signal ptr_inc : std_logic;
  signal ptr_dec : std_logic;

  --cnt
  signal cnt_reg : std_logic_vector(7 downto 0);
  signal cnt_inc : std_logic;
  signal cnt_dec : std_logic;

  --mux
  signal mux_data_addr_sel : std_logic; 

  --mux2
  signal mux2_data_wdata_sel : std_logic_vector(1 downto 0); 

begin
  --pc register
  pc_cnt : process (CLK, RESET)
  begin
    if (RESET = '1') then
      pc_reg <= ( others => '0');
    elsif (rising_edge(CLK)) then
      if (pc_inc = '1') then
        pc_reg <= pc_reg + 1;
      elsif (pc_dec = '1') then
        pc_reg <= pc_reg - 1;
      end if;
    end if;
  end process;

  --ptr register
  ptr_cnt : process (CLK, RESET)
  begin
    if (RESET = '1') then
      ptr_reg <= "1000000000000";
    elsif (rising_edge(CLK)) then
      if (ptr_inc = '1') then
        if ptr_reg = "1111111111111" then
          ptr_reg <= "1000000000000";
        else
          ptr_reg <= ptr_reg + 1;
          end if;
      elsif (ptr_dec = '1') then
          if ptr_reg = "1000000000000" then
            ptr_reg <= "1111111111111";
          else
            ptr_reg <= ptr_reg - 1;
        end if;
      end if;
    end if;
  end process;

  --cnt register
  cnt_cnt : process (CLK, RESET)
  begin
    if (RESET = '1') then
      cnt_reg <= (others => '0');
    elsif (rising_edge(CLK)) then
      if (cnt_inc = '1') then
        cnt_reg <= cnt_reg + 1;
      elsif (cnt_dec = '1') then
        cnt_reg <= cnt_reg - 1;
      end if;
    end if;
  end process;

  --mux
  mux : process (mux_data_addr_sel, pc_reg, ptr_reg) 
  begin
    if(mux_data_addr_sel = '0') then
      DATA_ADDR <= pc_reg;
    else
      DATA_ADDR <= ptr_reg;
    end if;
  end process;

  --mux2
  mux2_data_cnt : process (mux2_data_wdata_sel, DATA_RDATA, IN_DATA)
  begin
    case mux2_data_wdata_sel is
      when "00" => DATA_WDATA <= IN_DATA; 
      when "01" => DATA_WDATA <= DATA_RDATA + 1;
      when "10" => DATA_WDATA <= DATA_RDATA - 1;
      when others => DATA_WDATA <= DATA_RDATA;
    end case;
  end process;

  --start state
  stateS_reg: process (RESET, CLK, EN)
  begin
    if RESET = '1' then
      stateS <= state_start;
    elsif (rising_edge(CLK)) then
      if EN = '1' then
        stateS <= stateN;
      end if;
    end if;
  end process;

  --next state
  stateN_reg: process (stateS, IN_VLD, OUT_BUSY, DATA_RDATA)
  begin
    --inicializacia
    stateN <= state_start;
    pc_inc <= '0';
    pc_dec <= '0';
    ptr_inc <= '0';
    ptr_dec <= '0';
    cnt_inc <= '0';
    cnt_dec <= '0';
    mux_data_addr_sel <= '1';
    mux2_data_wdata_sel <= "00";
    OUT_WE <= '0';
    IN_REQ <= '0';
    DATA_EN <= '0';
    DATA_RDWR <= '0';
    OUT_DATA <= DATA_RDATA;

    case stateS is
    
      when state_start =>
        stateN <= state_fetch;

      when state_fetch =>
        DATA_EN <= '1';
        DATA_RDWR <= '0';
        mux_data_addr_sel <= '0';
        stateN <= state_decode;

      when state_decode =>
      case DATA_RDATA is
        when X"3E" => stateN <= state_ptr_inc; -- >
        when X"3C" => stateN <= state_ptr_dec; -- <
        when X"2B" => stateN <= state_value_inc; -- +
        when X"2D" => stateN <= state_value_dec; -- -
        when X"5B" => stateN <= state_while_start; -- [
        when X"5D" => stateN <= state_while_end; -- ]
        when X"2E" => stateN <= state_write; -- .
        when X"2C" => stateN <= state_read; -- ,
        when X"28" => stateN <= state_do; -- (
        when X"29" => stateN <= state_do_end; --)
        when X"00" => stateN <= state_stop; -- null 
        when others => stateN <= state_ignore; -- ignore
      end case;

------------------------------------------------------------------------------------ >
      when state_ptr_inc => 
        ptr_inc <= '1';
        pc_inc <= '1';
        stateN <= state_fetch;
------------------------------------------------------------------------------------ <
      when state_ptr_dec => 
        ptr_dec <= '1';
        pc_inc <= '1';
        stateN <= state_fetch;
------------------------------------------------------------------------------------ +
      when state_value_inc => 
        DATA_EN <= '1';
        DATA_RDWR <= '0';
        stateN <= state_value_inc_next;

      when state_value_inc_next =>
        mux_data_addr_sel <= '1';
        mux2_data_wdata_sel <= "01";
        DATA_EN <= '1';
        DATA_RDWR <= '1';
        pc_inc <= '1';
        stateN <= state_fetch;
------------------------------------------------------------------------------------ -
      when state_value_dec => 
        DATA_EN <= '1';
        DATA_RDWR <= '0';
        stateN <= state_value_dec_next;
      when state_value_dec_next =>
        mux_data_addr_sel <= '1';
        mux2_data_wdata_sel <= "10";
        DATA_EN <= '1';
        DATA_RDWR <= '1';
        pc_inc <= '1';
        stateN <= state_fetch;
------------------------------------------------------------------------------------ [
      when state_while_start =>  
        pc_inc <= '1';
        DATA_EN <= '1';
        DATA_RDWR <= '0';
        mux_data_addr_sel <= '1';
        stateN <= state_while_next;
      
      when state_while_next =>
        if DATA_RDATA = "00000000" then
          cnt_inc <= '1';
          stateN <= state_while_next2;
        else
          stateN <= state_fetch;
        end if;
          
      when state_while_next2 =>
        if cnt_reg = "00000000" then
            stateN <= state_fetch;
        else
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          mux_data_addr_sel <= '0';
          stateN <= state_while_next3;
        end if ;
        
      when state_while_next3 =>
        if DATA_RDATA = X"5B" then
          cnt_inc <= '1';
        elsif DATA_RDATA = X"5D" then
            cnt_dec <= '1';
        end if ;
        pc_inc <= '1';
        stateN <= state_while_next2;
------------------------------------------------------------------------------------ ]
      when state_while_end => 
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          mux_data_addr_sel <= '1';
          stateN <= state_while_end_next;
    
      when state_while_end_next =>
        if DATA_RDATA = "00000000" then
          pc_inc <= '1';
          stateN <= state_fetch;
        else
          cnt_inc <= '1';
          pc_dec <= '1';
          stateN <= state_while_end_next2;
        end if;
    
      when state_while_end_next2 =>
        if cnt_reg <= "00000000" then
          stateN <= state_fetch;
        else
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          mux_data_addr_sel <= '0';
          stateN <= state_while_end_next3;
        end if;

      when state_while_end_next3 =>
        if DATA_RDATA = X"5B" then
          cnt_dec <= '1';
        elsif DATA_RDATA = X"5D" then
          cnt_inc <= '1';
        elsif DATA_RDATA = X"28" then
          cnt_dec <= '1';
        elsif DATA_RDATA = X"29" then
          cnt_inc <= '1';
        end if ;
        stateN <= state_while_end_next4;
    
      when state_while_end_next4 =>
        DATA_EN <= '1';
        if cnt_reg = "00000000" then
          pc_inc <= '1';
        else
          pc_dec <= '1';
        end if;
        stateN <= state_while_end_next2;
------------------------------------------------------------------------------------ (
      when state_do =>
        DATA_EN <= '1';
        DATA_RDWR <= '0';
        mux_data_addr_sel <= '1';
        stateN <= state_do_next;

      when state_do_next =>
        pc_inc <= '1';
        stateN <= state_fetch;
------------------------------------------------------------------------------------ )
      when state_do_end =>
        DATA_EN <= '1';
        mux_data_addr_sel <= '1';
        stateN <= state_do_end_next2;

      when state_do_end_next2 =>
        mux_data_addr_sel <= '1';
        if DATA_RDATA = "00000000" then
          pc_inc <= '1';
          stateN <= state_fetch;
        else
          DATA_EN <= '1';
          cnt_inc <= '1';
          pc_dec <= '1';
          stateN <= state_do_end_next3;
        end if;

      when state_do_end_next3 =>
        if cnt_reg = "00000000" then
          stateN <= state_fetch;
        else
          DATA_EN <= '1';
          DATA_RDWR <= '0';
          mux_data_addr_sel <= '0';
          stateN <= state_do_end_next4;
        end if;

      when state_do_end_next4 =>
        if DATA_RDATA = X"5D" then
          cnt_inc <= '1';
        elsif DATA_RDATA = X"5B" then
          cnt_dec <= '1';
        elsif DATA_RDATA = X"29" then
          cnt_inc <= '1';
        elsif DATA_RDATA = X"28" then
          cnt_dec <= '1';
        end if;
        stateN <= state_do_end_next5;

      when state_do_end_next5 =>
        DATA_EN <= '1';
        if cnt_reg = "00000000" then
          pc_inc <= '1';
        else
          pc_dec <= '1';
        end if;
        stateN <= state_do_end_next3;
------------------------------------------------------------------------------------ .
      when state_write =>
        DATA_EN <= '1';
        DATA_RDWR <= '0';
        stateN <= state_write_next;

      when state_write_next =>
        mux_data_addr_sel <= '1';
        if OUT_BUSY = '0' then
          OUT_WE <= '1';
          OUT_DATA <= DATA_RDATA;
          pc_inc <= '1';
          stateN <= state_fetch;
        else
          stateN <= state_write;
        end if;  
------------------------------------------------------------------------------------ ,
      when state_read =>
        DATA_EN <= '1';
        IN_REQ <= '1';
        DATA_RDWR <= '0';
        mux_data_addr_sel <= '1';
        stateN <= state_read_next;

      when state_read_next =>
        if IN_VLD = '1' then
          mux2_data_wdata_sel <= "00";
          DATA_EN <= '1';
          DATA_RDWR <= '1';
          pc_inc <= '1';
          stateN <= state_fetch;
        else
          stateN <= state_read;
        end if;
------------------------------------------------------------------------------------ stop
      when state_stop => stateN <= state_stop;
------------------------------------------------------------------------------------ ignore
      when state_ignore =>
        pc_inc <= '1';
        stateN <= state_fetch;
------------------------------------------------------------------------------------ others
      when others => null; 
------------------------------------------------------------------------------------ end
    end case;
  end process;
end behavioral;