-------------------------------------------------------------------------------
-- Title      :
-- Project    : Wishbone2AXI
-------------------------------------------------------------------------------
-- File       : WishboneAXI_v0_1_S_AXI4_LITE.vhd
-- Authors    : Adrian Byszuk <adrian.byszuk@gmail.com>
--            : Piotr Miedzik (Qermit)
-- Company    :
-- Created    : 2016-06-06
-- Last update: 2016-06-23
-- License    : This is a PUBLIC DOMAIN code, published under
--              Creative Commons CC0 license
-- Platform   :
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: AXI Lite -> WB bridge
-------------------------------------------------------------------------------
-- Copyright (c) 2016
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 2016-05-13  1.0      abyszuk    Created
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Implementation details
-------------------------------------------------------------------------------
-- In the AXI bus the read and write accesses may be handled independently
-- but in Wishbone they can't, therefore we must provide an arbitration scheme.
-- We assume "Write before read"
-- To ease bridging, both AXI and WB use byte addressing. WB uses byte select.


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.genram_pkg.all;

entity WishboneAXI_v0_1_S_AXI4_LITE is
  generic (
    -- Users to add parameters here
    C_WB_ADR_WIDTH : integer;
    C_WB_DAT_WIDTH : integer;
    C_WB_MODE      : string;            --"CLASSIC", "PIPELINED"
    -- User parameters ends
    -- Do not modify the parameters beyond this line

    -- Width of S_AXI data bus
    C_S_AXI_DATA_WIDTH : integer := 32;
    -- Width of S_AXI address bus
    C_S_AXI_ADDR_WIDTH : integer := 4
    );
  port (
    -- Users to add ports here
    m_wb_areset : in  std_logic;
    m_wb_adr    : out std_logic_vector(C_WB_ADR_WIDTH-1 downto 0);
    m_wb_dat_w  : out std_logic_vector(C_WB_DAT_WIDTH-1 downto 0);
    m_wb_cyc    : out std_logic;
    m_wb_stb    : out std_logic;
    m_wb_lock   : out std_logic;
    m_wb_sel    : out std_logic_vector(C_WB_DAT_WIDTH/8-1 downto 0);
    m_wb_we     : out std_logic;
    m_wb_dat_r  : in  std_logic_vector(C_WB_DAT_WIDTH-1 downto 0);
    m_wb_stall  : in  std_logic;
    m_wb_err    : in  std_logic;
    m_wb_rty    : in  std_logic;
    m_wb_ack    : in  std_logic;
    -- User ports ends
    -- Do not modify the ports beyond this line

    -- Global Clock Signal
    S_AXI_ACLK    : in  std_logic;
    -- Global Reset Signal. This Signal is Active LOW
    S_AXI_ARESETN : in  std_logic;
    -- Write address (issued by master, acceped by Slave)
    S_AXI_AWADDR  : in  std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
    -- Write channel Protection type. This signal indicates the
    -- privilege and security level of the transaction, and whether
    -- the transaction is a data access or an instruction access.
    S_AXI_AWPROT  : in  std_logic_vector(2 downto 0);
    -- Write address valid. This signal indicates that the master signaling
    -- valid write address and control information.
    S_AXI_AWVALID : in  std_logic;
    -- Write address ready. This signal indicates that the slave is ready
    -- to accept an address and associated control signals.
    S_AXI_AWREADY : out std_logic;
    -- Write data (issued by master, acceped by Slave) 
    S_AXI_WDATA   : in  std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    -- Write strobes. This signal indicates which byte lanes hold
    -- valid data. There is one write strobe bit for each eight
    -- bits of the write data bus.    
    S_AXI_WSTRB   : in  std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
    -- Write valid. This signal indicates that valid write
    -- data and strobes are available.
    S_AXI_WVALID  : in  std_logic;
    -- Write ready. This signal indicates that the slave
    -- can accept the write data.
    S_AXI_WREADY  : out std_logic;
    -- Write response. This signal indicates the status
    -- of the write transaction.
    S_AXI_BRESP   : out std_logic_vector(1 downto 0);
    -- Write response valid. This signal indicates that the channel
    -- is signaling a valid write response.
    S_AXI_BVALID  : out std_logic;
    -- Response ready. This signal indicates that the master
    -- can accept a write response.
    S_AXI_BREADY  : in  std_logic;
    -- Read address (issued by master, acceped by Slave)
    S_AXI_ARADDR  : in  std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
    -- Protection type. This signal indicates the privilege
    -- and security level of the transaction, and whether the
    -- transaction is a data access or an instruction access.
    S_AXI_ARPROT  : in  std_logic_vector(2 downto 0);
    -- Read address valid. This signal indicates that the channel
    -- is signaling valid read address and control information.
    S_AXI_ARVALID : in  std_logic;
    -- Read address ready. This signal indicates that the slave is
    -- ready to accept an address and associated control signals.
    S_AXI_ARREADY : out std_logic;
    -- Read data (issued by slave)
    S_AXI_RDATA   : out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    -- Read response. This signal indicates the status of the
    -- read transfer.
    S_AXI_RRESP   : out std_logic_vector(1 downto 0);
    -- Read valid. This signal indicates that the channel is
    -- signaling the required read data.
    S_AXI_RVALID  : out std_logic;
    -- Read ready. This signal indicates that the master can
    -- accept the read data and response information.
    S_AXI_RREADY  : in  std_logic
    );
end WishboneAXI_v0_1_S_AXI4_LITE;

architecture arch_imp of WishboneAXI_v0_1_S_AXI4_LITE is

  type t_trans_state is (IDLE, AW_LATCH, W_LATCH, W_SEND, W_RESP, R_SEND, R_RESP);
  signal trans_state : t_trans_state := IDLE;

  -- AXI4LITE signals
  signal axi_awready      : std_logic;
  signal axi_wready       : std_logic;
  signal axi_wdata        : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
  signal axi_bresp        : std_logic_vector(1 downto 0);
  signal axi_bvalid       : std_logic;
  signal axi_arready      : std_logic;
  signal axi_rdata        : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
  signal axi_rresp        : std_logic_vector(1 downto 0);
  signal axi_rvalid       : std_logic;
  signal axi_araddr       : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
  signal axi_araddr_read  : std_logic := '0';
  signal axi_araddr_empty : std_logic;
  signal axi_araddr_full  : std_logic;

  signal wb_adr   : std_logic_vector(C_WB_ADR_WIDTH-1 downto 0);
  signal wb_dat_w : std_logic_vector(C_WB_DAT_WIDTH-1 downto 0);
  signal wb_cyc   : std_logic;
  signal wb_stb   : std_logic;
  signal wb_lock  : std_logic;
  signal wb_sel   : std_logic_vector(C_WB_DAT_WIDTH/8-1 downto 0);
  signal wb_we    : std_logic;

begin

  translate : process (S_AXI_ACLK) is
  begin
    if rising_edge(S_AXI_ACLK) then
      if S_AXI_ARESETN = '0' or m_wb_areset = '1' then
        axi_awready <= '0';
        axi_wready  <= '0';
        axi_bresp   <= "00";
        axi_bvalid  <= '0';
        axi_rdata   <= (others => '0');
        axi_rresp   <= "00";
        axi_rvalid  <= '0';
        wb_adr      <= (others => '0');
        wb_dat_w    <= (others => '0');
        wb_cyc      <= '0';
        wb_stb      <= '0';
        wb_lock     <= '0';
        wb_sel      <= (others => '0');
        wb_we       <= '0';
        trans_state <= IDLE;
      else
        case trans_state is
          when IDLE =>
            --keep [awready, wready] high to avoid wasting clock cycles
            axi_awready <= '1';
            axi_wready  <= '1';
            axi_bvalid  <= '0';
            axi_rvalid  <= '0';
            wb_cyc      <= '0';
            -- stb not necessary by spec., but lack of this probably will wreak havoc amongst badly implemented slaves
            wb_stb      <= '0';

            if (axi_awready and S_AXI_AWVALID) = '1' and (axi_wready and S_AXI_WVALID) = '0' then
              axi_awready <= '0';
              wb_adr      <= S_AXI_AWADDR;
              trans_state <= AW_LATCH;
            elsif (axi_awready and S_AXI_AWVALID) = '0' and (axi_wready and S_AXI_WVALID) = '1' then
              axi_wready  <= '0';
              wb_dat_w    <= S_AXI_WDATA;
              wb_sel      <= S_AXI_WSTRB;
              trans_state <= W_LATCH;
            elsif (axi_awready and S_AXI_AWVALID) = '1' and (axi_wready and S_AXI_WVALID) = '1' then
              axi_awready <= '0';
              axi_wready  <= '0';
              wb_cyc      <= '1'; --push cycle to WB as soon as possible
              wb_stb      <= '1';
              wb_we       <= '1';
              wb_adr      <= S_AXI_AWADDR;
              wb_dat_w    <= S_AXI_WDATA;
              wb_sel      <= S_AXI_WSTRB;
              trans_state <= W_SEND;
            elsif axi_araddr_empty = '0' then
              wb_adr      <= axi_araddr;
              wb_cyc      <= '1';
              wb_stb      <= '1';
              wb_we       <= '0';
              trans_state <= R_SEND;
            end if;
          --AXI specification explicitly says that no relationship between input channels is defined (A3.3)
          --It means that write data can appear before write address and vice versa. It is slave's responsibility
          --to align channels if that's necessary for proper slave operation.
          when AW_LATCH =>
            axi_awready <= '0';
            if (axi_wready and S_AXI_WVALID) = '1' then
              axi_wready  <= '0';
              wb_cyc      <= '1';
              wb_stb      <= '1';
              wb_we       <= '1';
              wb_dat_w    <= S_AXI_WDATA;
              wb_sel      <= S_AXI_WSTRB;
              trans_state <= W_SEND;
            end if;

          when W_LATCH =>
            axi_wready <= '0';
            if (axi_awready and S_AXI_AWVALID) = '1' then
              axi_awready <= '0';
              wb_cyc      <= '1';
              wb_stb      <= '1';
              wb_we       <= '1';
              wb_adr      <= S_AXI_AWADDR;
              trans_state <= W_SEND;
            end if;

          --W_SEND state is quite complicated and delicate. We want to support back-to-back transactions when it's
          --possible. But to do that Classic WB slave must support asynchronous cycle termination and AXI-LITE master
          --has to push aligned transfers on AW and W channels AND have response channel ready.
          when W_SEND =>
            axi_awready <= '0';
            axi_wready  <= '0';
            axi_bresp   <= "00";
            axi_bvalid  <= '0';
            wb_cyc      <= '1';
            wb_stb      <= '1';
            wb_we       <= '1';
            if C_WB_MODE = "CLASSIC" then
              if (m_wb_ack or m_wb_err or m_wb_rty) = '1' then
                axi_bresp(1) <= not(m_wb_ack);  --if it's not ACK, then it must be slave error
                axi_bvalid   <= '1';
                wb_stb       <= '0';  --only strobe, keep cycle high in hope of new data
                if S_AXI_BREADY = '0' then
                  trans_state <= W_RESP;
                -- according to AXI spec. *VALID signal, once asserted, *must* remain asserted until *READY is asserted
                -- so we can latch data and set *ready in next cycle
                elsif (S_AXI_AWVALID and S_AXI_WVALID) = '1' then
                  axi_awready <= '1';
                  axi_wready  <= '1';  --toogle ready signals to latch axi data
                  wb_stb      <= '1';
                  wb_adr      <= S_AXI_AWADDR;
                  wb_dat_w    <= S_AXI_WDATA;
                  wb_sel      <= S_AXI_WSTRB;
                else
                  axi_awready <= '1';
                  axi_wready  <= '1';  --prepare early for next cycle
                  wb_cyc      <= '0';
                  trans_state <= IDLE;
                end if;
              end if;
            end if;

          when W_RESP =>
            axi_awready <= '0';
            axi_wready  <= '0';
            axi_bresp   <= axi_bresp;
            axi_bvalid  <= '1';
            wb_stb      <= '0';
            if C_WB_MODE = "CLASSIC" then
              if S_AXI_BREADY = '1' then
                axi_bvalid <= '0';
                if (S_AXI_AWVALID and S_AXI_WVALID) = '1' then
                  axi_awready <= '1';
                  axi_wready  <= '1';  --toogle ready signals to latch axi data
                  wb_cyc      <= '1';
                  wb_stb      <= '1';
                  wb_we       <= '1';
                  wb_adr      <= S_AXI_AWADDR;
                  wb_dat_w    <= S_AXI_WDATA;
                  wb_sel      <= S_AXI_WSTRB;
                  trans_state <= W_SEND;
                else
                  axi_awready <= '1';
                  axi_wready  <= '1';   --prepare early for next cycle
                  wb_cyc      <= '0';
                  trans_state <= IDLE;
                end if;
              end if;
            end if;

          when R_SEND =>
            axi_rresp  <= "00";
            axi_rvalid <= '0';
            wb_cyc     <= '1';
            wb_stb     <= '1';
            wb_we      <= '0';
            if C_WB_MODE = "CLASSIC" then
              if (m_wb_ack or m_wb_err or m_wb_rty) = '1' then
                axi_rdata    <= m_wb_dat_r;
                axi_rresp(1) <= not(m_wb_ack);
                axi_rvalid   <= '1';
                wb_stb       <= '0';
                if S_AXI_RREADY = '0' then
                  trans_state <= R_RESP;
                elsif axi_araddr_empty = '0' then
                  wb_adr <= axi_araddr;
                  wb_stb <= '1';
                else
                  wb_cyc      <= '0';
                  trans_state <= R_RESP;
                end if;
              end if;
            end if;

          when R_RESP =>
            axi_rresp  <= axi_rresp;
            axi_rvalid <= '1';
            wb_stb     <= '0';
            if C_WB_MODE = "CLASSIC" then
              if S_AXI_RREADY = '1' then
                axi_rvalid <= '0';
                if axi_araddr_empty = '0' then
                  wb_adr      <= axi_araddr;
                  wb_stb      <= '1';
                  trans_state <= R_SEND;
                else
                  wb_cyc      <= '0';
                  trans_state <= IDLE;
                end if;
              end if;
            end if;
--coverage off
          when others =>
            axi_awready <= '0';
            axi_wready  <= '0';
            axi_bvalid  <= '0';
            axi_rvalid  <= '0';
            wb_cyc      <= '0';
            wb_stb      <= '0';
            trans_state <= IDLE;
--coverage on
        end case;
      end if;
    end if;
  end process;

  --used to drive some specific signals which need to change state in the same clock cycle
  translate_comb : process(trans_state, S_AXI_RREADY, axi_araddr_empty, m_wb_ack, m_wb_err, m_wb_rty)
  begin
    case trans_state is
      when IDLE =>
        axi_araddr_read <= '0';
        if axi_araddr_empty = '0' then
          axi_araddr_read <= '1';
        end if;

      when R_SEND =>
        axi_araddr_read <= '0';
        if C_WB_MODE = "CLASSIC" then
          if (m_wb_ack or m_wb_err or m_wb_rty) = '1' then
            if axi_araddr_empty = '0' and S_AXI_RREADY = '1' then  --start next read asap to support b2b reads
              axi_araddr_read <= '1';
            end if;
          end if;
        end if;
      when R_RESP =>
        axi_araddr_read <= '0';
        if C_WB_MODE = "CLASSIC" then
          if S_AXI_RREADY = '1' then
            if axi_araddr_empty = '0' then
              axi_araddr_read <= '1';
            end if;
          end if;
        end if;

      when others =>
        axi_araddr_read <= '0';

    end case;
  end process;

  --To avoid wasted cycles put read requests on a queue. Combined with Wishbone's asynchronous cycle
  --termination or pipelined mode will prove very useful for achieving high bus throughput.
  ar_queue : inferred_sync_fifo
    generic map (
      g_data_width        => C_S_AXI_ADDR_WIDTH,
      g_size              => 4,
      g_show_ahead        => true,
      g_with_empty        => true,
      g_with_full         => true,
      g_with_almost_empty => false,
      g_with_almost_full  => false,
      g_with_count        => false
      )
    port map (
      rst_n_i => S_AXI_ARESETN,
      clk_i   => S_AXI_ACLK,
      d_i     => S_AXI_ARADDR,
      we_i    => S_AXI_ARVALID,
      q_o     => axi_araddr,
      rd_i    => axi_araddr_read,
      empty_o => axi_araddr_empty,
      full_o  => axi_araddr_full
      );

  axi_arready <= '0' when S_AXI_ARESETN = '0' else not(axi_araddr_full); --to comply with spec under reset
  -- I/O Connections assignments
  S_AXI_AWREADY <= axi_awready;
  S_AXI_WREADY  <= axi_wready;
  S_AXI_BRESP   <= axi_bresp;
  S_AXI_BVALID  <= axi_bvalid;
  S_AXI_ARREADY <= axi_arready;
  S_AXI_RDATA   <= axi_rdata;
  S_AXI_RRESP   <= axi_rresp;
  S_AXI_RVALID  <= axi_rvalid;

  m_wb_adr   <= wb_adr;
  m_wb_dat_w <= wb_dat_w;
  m_wb_cyc   <= wb_cyc;
  m_wb_stb   <= wb_stb;
  m_wb_lock  <= wb_lock;
  m_wb_sel   <= wb_sel;
  m_wb_we    <= wb_we;


  assert (C_S_AXI_DATA_WIDTH = C_WB_DAT_WIDTH)
    report "AXI-Lite->Wishbone bridge doesn't support data width conversion. " & lf &
    "C_S_AXI_DATA_WIDTH=" & integer'image(C_S_AXI_DATA_WIDTH) &
    " C_WB_DAT_WIDTH=" & integer'image(C_WB_DAT_WIDTH)
    severity failure;

  assert (C_WB_MODE = "CLASSIC" or C_WB_MODE = "PIPELINED")
    report "Incorrect C_WB_MODE: " & C_WB_MODE
    severity failure;

end arch_imp;
