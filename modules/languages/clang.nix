{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
with builtins; let
  cfg = config.vim.languages.clang;

  defaultServer = "ccls";
  packageToCmd = package: defaultCmd:
    if isList cfg.lsp.package
    then nvim.lua.expToLua cfg.lsp.package
    else ''{ "${cfg.lsp.package}/bin/${defaultCmd}" }'';
  servers = {
    ccls = {
      package = pkgs.ccls;
      lspConfig = ''
        lspconfig.ccls.setup{
          capabilities = capabilities;
          on_attach=default_on_attach;
          cmd = ${packageToCmd cfg.lsp.package "ccls"};
          ${optionalString (cfg.lsp.opts != null) "init_options = ${cfg.lsp.opts}"}
        }
      '';
    };
    clangd = {
      package = pkgs.clang-tools_16;
      lspConfig = ''
        local clangd_cap = capabilities
        -- use same offsetEncoding as null-ls
        clangd_cap.offsetEncoding = {"utf-16"}
        lspconfig.clangd.setup{
          capabilities = clangd_cap;
          on_attach=default_on_attach;
          cmd = ${packageToCmd cfg.lsp.package "clangd"};
          ${optionalString (cfg.lsp.opts != null) "init_options = ${cfg.lsp.opts}"}
        }
      '';
    };
  };

  defaultDebugger = "lldb-vscode";
  debuggers = {
    lldb-vscode = {
      package = pkgs.lldb;
      dapConfig = ''
        dap.adapters.lldb = {
          type = 'executable',
          command = '${cfg.dap.package}/bin/lldb-vscode',
          name = 'lldb'
        }
        dap.configurations.cpp = {
          {
            name = 'Launch',
            type = 'lldb',
            request = 'launch',
            program = function()
              return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
            end,
            cwd = "''${workspaceFolder}",
            stopOnEntry = false,
            args = {},
          },
        }

        dap.configurations.c = dap.configurations.cpp
      '';
    };
  };
in {
  options.vim.languages.clang = {
    enable = mkEnableOption "C/C++ language support";

    cHeader = mkOption {
      description = ''
        C syntax for headers. Can fix treesitter errors, see:
        https://www.reddit.com/r/neovim/comments/orfpcd/question_does_the_c_parser_from_nvimtreesitter/
      '';
      type = types.bool;
      default = false;
    };

    treesitter = {
      enable = mkEnableOption "C/C++ treesitter" // {default = config.vim.languages.enableTreesitter;};
      cPackage = nvim.types.mkGrammarOption pkgs "c";
      cppPackage = nvim.types.mkGrammarOption pkgs "cpp";
    };

    lsp = {
      enable = mkEnableOption "Enable clang LSP support" // {default = config.vim.languages.enableLSP;};

      server = mkOption {
        description = "The clang LSP server to use";
        type = with types; enum (attrNames servers);
        default = defaultServer;
      };

      package = mkOption {
        description = "clang LSP server package, or the command to run as a list of strings";
        example = ''[lib.getExe pkgs.jdt-language-server " - data " " ~/.cache/jdtls/workspace "]'';
        type = with types; either package (listOf str);
        default = servers.${cfg.lsp.server}.package;
      };

      opts = mkOption {
        description = "Options to pass to clang LSP server";
        type = with types; nullOr str;
        default = null;
      };
    };

    dap = {
      enable = mkOption {
        description = "Enable clang Debug Adapter";
        type = types.bool;
        default = config.vim.languages.enableDAP;
      };
      debugger = mkOption {
        description = "clang debugger to use";
        type = with types; enum (attrNames debuggers);
        default = defaultDebugger;
      };
      package = mkOption {
        description = "clang debugger package.";
        type = types.package;
        default = debuggers.${cfg.dap.debugger}.package;
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    (mkIf cfg.cHeader {
      vim.configRC.c-header = nvim.dag.entryAnywhere "let g:c_syntax_for_h = 1";
    })

    (mkIf cfg.treesitter.enable {
      vim.treesitter.enable = true;
      vim.treesitter.grammars = [cfg.treesitter.cPackage cfg.treesitter.cppPackage];
    })

    (mkIf cfg.lsp.enable {
      vim.lsp.lspconfig.enable = true;

      vim.lsp.lspconfig.sources.clang-lsp = servers.${cfg.lsp.server}.lspConfig;
    })

    (mkIf cfg.dap.enable {
      vim.debugger.nvim-dap.enable = true;
      vim.debugger.nvim-dap.sources.clang-debugger = debuggers.${cfg.dap.debugger}.dapConfig;
    })
  ]);
}
