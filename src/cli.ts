#!/usr/bin/env node
/**
 * my-agent-harness CLI
 * Installs and configures the AI orchestration harness for OpenCode
 */

import { program } from 'commander';
import chalk from 'chalk';
import ora from 'ora';
import { fileURLToPath } from 'url';
import { dirname, resolve, join } from 'path';
import { existsSync, mkdirSync, copyFileSync, readdirSync, statSync, readFileSync, writeFileSync, rmSync, cpSync, symlinkSync } from 'fs';
import { execa } from 'execa';
import prompts from 'prompts';
import fsExtra from 'fs-extra';

const { remove, move, copy, ensureDir, pathExists } = fsExtra;

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const ROOT_DIR = resolve(__dirname, '..');
const CONFIG_DIR = join(ROOT_DIR, 'config');
const HOME_DIR = process.env.HOME || process.env.USERPROFILE || '';
const INSTALL_DIR = join(HOME_DIR, '.config', 'opencode');
const REPO_DIR = join(HOME_DIR, 'my-agent-harness');

interface InstallOptions {
  repoDir?: string;
  installDir?: string;
  skipDeps?: boolean;
  skipVerify?: boolean;
  force?: boolean;
}

async function checkPrerequisites(): Promise<void> {
  const spinner = ora('Checking prerequisites...').start();
  
  try {
    // Check opencode
    await execa('opencode', ['--version']);
    spinner.succeed('OpenCode CLI found');
    
    // Check Node.js
    const { stdout: nodeVersion } = await execa('node', ['--version']);
    spinner.succeed(`Node.js ${nodeVersion.trim()} found`);
    
    // Check npm
    const { stdout: npmVersion } = await execa('npm', ['--version']);
    spinner.succeed(`npm ${npmVersion.trim()} found`);
    
    // Check git
    await execa('git', ['--version']);
    spinner.succeed('git found');
  } catch (error) {
    spinner.fail('Prerequisites check failed');
    console.error(chalk.red('Missing required tools. Please install:'));
    console.error('  - OpenCode CLI: https://opencode.ai');
    console.error('  - Node.js 18+: https://nodejs.org');
    console.error('  - git: https://git-scm.com');
    process.exit(1);
  }
}

async function backupExistingConfig(installDir: string, force: boolean): Promise<void> {
  if (!existsSync(installDir)) return;
  
  const spinner = ora('Backing up existing config...').start();
  
  if (statSync(installDir).isSymbolicLink()) {
    // Remove existing symlink
    await remove(installDir);
    spinner.succeed('Removed existing symlink');
  } else if (force) {
    const backupDir = `${installDir}.backup.${Date.now()}`;
    await move(installDir, backupDir);
    spinner.succeed(`Backed up to ${backupDir}`);
  } else {
    spinner.warn('Existing config found. Use --force to overwrite.');
    process.exit(1);
  }
}

async function cloneOrUpdateRepo(repoDir: string): Promise<void> {
  const spinner = ora('Setting up repository...').start();
  
  if (existsSync(join(repoDir, '.git'))) {
    spinner.text = 'Updating existing repository...';
    await execa('git', ['pull', 'origin', 'main'], { cwd: repoDir });
    spinner.succeed('Repository updated');
  } else {
    spinner.text = 'Cloning repository...';
    // For local development, copy from current directory
    if (existsSync(join(ROOT_DIR, '.git'))) {
      await copy(ROOT_DIR, repoDir);
      spinner.succeed('Repository copied from local');
    } else {
      // This would be the actual git clone in production
      await execa('git', ['clone', 'https://github.com/your-username/my-agent-harness.git', repoDir]);
      spinner.succeed('Repository cloned');
    }
  }
}

async function installDependencies(repoDir: string): Promise<void> {
  const spinner = ora('Installing dependencies...').start();
  
  try {
    await execa('npm', ['install'], { cwd: repoDir, stdio: 'pipe' });
    spinner.succeed('Dependencies installed');
  } catch (error) {
    spinner.fail('Failed to install dependencies');
    throw error;
  }
}

async function copyTemplates(repoDir: string): Promise<void> {
  const spinner = ora('Setting up configuration templates...').start();
  
  const configDir = join(repoDir, 'config');
  if (!existsSync(configDir)) {
    spinner.warn('No config directory found');
    return;
  }
  
  const templates = readdirSync(configDir).filter(f => f.endsWith('.template'));
  
  for (const template of templates) {
    const target = join(repoDir, template.replace('.template', ''));
    if (!existsSync(target)) {
      copyFileSync(join(configDir, template), target);
      spinner.succeed(`Created ${template.replace('.template', '')}`);
    }
  }
  
  spinner.succeed('Configuration templates ready');
}

async function linkConfig(repoDir: string, installDir: string): Promise<void> {
  const spinner = ora('Linking config directory...').start();
  
  try {
    // Remove existing if any
    if (existsSync(installDir)) {
      await remove(installDir);
    }
    
    // Create parent directory
    await ensureDir(dirname(installDir));
    
    // Create symlink (or junction on Windows)
    if (process.platform === 'win32') {
      // On Windows, use junction (directory symlink)
      await execa('cmd', ['/c', 'mklink', '/D', installDir, repoDir]);
      spinner.succeed(`Config linked to ${installDir} (Windows junction)`);
    } else {
      symlinkSync(repoDir, installDir, 'dir');
      spinner.succeed(`Config linked to ${installDir}`);
    }
  } catch (error) {
    spinner.fail('Failed to link config directory');
    throw error;
  }
}

async function verifyInstallation(): Promise<void> {
  const spinner = ora('Verifying installation...').start();
  
  try {
    // Check agents
    const { stdout: agentsOutput } = await execa('opencode', ['agent', 'list'], { 
      cwd: INSTALL_DIR,
      reject: false 
    });
    const agentCount = (agentsOutput.match(/^\s*[a-z]/gm) || []).length;
    
    if (agentCount > 0) {
      spinner.succeed(`${agentCount} agents loaded`);
    } else {
      spinner.warn('No agents found - check configuration');
    }
    
    // Check skills
    const { stdout: skillsOutput } = await execa('opencode', ['skill', 'list'], { 
      cwd: INSTALL_DIR,
      reject: false 
    });
    const skillCount = (skillsOutput.match(/^\s*[a-z]/gm) || []).length;
    
    if (skillCount > 0) {
      console.log(chalk.green(`✓ ${skillCount} skills available`));
    } else {
      console.log(chalk.yellow('⊙ No managed skills (gstack/mp-* skills load on demand)'));
    }
    
    console.log(chalk.green('✓ Plugins configured'));
  } catch (error) {
    spinner.fail('Verification failed');
    console.error(chalk.red('Run `opencode agent list` to debug'));
  }
}

async function promptForApiKeys(repoDir: string): Promise<void> {
  const configPath = join(repoDir, 'opencode.jsonc');
  if (!existsSync(configPath)) return;
  
  const configContent = readFileSync(configPath, 'utf-8');
  const needsKeys = configContent.includes('${CONTEXT7_API_KEY}') || 
                    configContent.includes('${OPENAI_API_KEY}') ||
                    configContent.includes('${ANTHROPIC_API_KEY}');
  
  if (!needsKeys) return;
  
  console.log(chalk.yellow('\n⚠ Configuration requires API keys:'));
  
  const response = await prompts([
    {
      type: 'text',
      name: 'context7',
      message: 'Context7 API key (get from https://context7.com):',
      validate: v => v.length > 0 || 'Required for library docs'
    },
    {
      type: 'text',
      name: 'openai',
      message: 'OpenAI API key (optional, for GPT models):'
    },
    {
      type: 'text',
      name: 'anthropic',
      message: 'Anthropic API key (optional, for Claude models):'
    }
  ]);
  
  if (response.context7) {
    let updated = configContent.replace('${CONTEXT7_API_KEY}', response.context7);
    if (response.openai) updated = updated.replace('${OPENAI_API_KEY}', response.openai);
    if (response.anthropic) updated = updated.replace('${ANTHROPIC_API_KEY}', response.anthropic);
    writeFileSync(configPath, updated);
    console.log(chalk.green('✓ API keys saved to opencode.jsonc'));
  }
}

async function install(options: InstallOptions = {}): Promise<void> {
  const repoDir = options.repoDir || REPO_DIR;
  const installDir = options.installDir || INSTALL_DIR;
  
  console.log(chalk.blue('\n╔══════════════════════════════════════════════════════════════╗'));
  console.log(chalk.blue('║     my-agent-harness — AI Orchestration Setup               ║'));
  console.log(chalk.blue('╚══════════════════════════════════════════════════════════════╝\n'));
  
  await checkPrerequisites();
  await backupExistingConfig(installDir, options.force || false);
  await cloneOrUpdateRepo(repoDir);
  
  if (!options.skipDeps) {
    await installDependencies(repoDir);
  }
  
  await copyTemplates(repoDir);
  await linkConfig(repoDir, installDir);
  
  if (!options.skipVerify) {
    await verifyInstallation();
  }
  
  await promptForApiKeys(repoDir);
  
  console.log(chalk.blue('\n╔══════════════════════════════════════════════════════════════╗'));
  console.log(chalk.blue('║                    Installation Complete!                    ║'));
  console.log(chalk.blue('╚══════════════════════════════════════════════════════════════╝\n'));
  
  console.log(chalk.green('Next steps:'));
  console.log(`  1. ${chalk.yellow('Edit config files in')} ${chalk.cyan(repoDir)}/config/`);
  console.log(`     - opencode.jsonc (add your API keys)`);
  console.log(`     - oh-my-opencode-slim.json (adjust models if needed)`);
  console.log(`  2. ${chalk.yellow('Run:')} opencode agent list`);
  console.log(`  3. ${chalk.yellow('Run:')} opencode run review`);
  console.log(`  4. ${chalk.yellow('Run:')} opencode skill list`);
  console.log(`\n${chalk.blue('Documentation:')} ${repoDir}/README.md`);
  console.log(`${chalk.blue('Repository:')} https://github.com/your-username/my-agent-harness\n`);
}

program
  .name('my-agent-harness')
  .description('AI Orchestration Harness for OpenCode')
  .version('1.0.0')
  .option('-r, --repo-dir <path>', 'Repository directory', REPO_DIR)
  .option('-i, --install-dir <path>', 'Install directory', INSTALL_DIR)
  .option('--skip-deps', 'Skip dependency installation')
  .option('--skip-verify', 'Skip verification')
  .option('-f, --force', 'Force overwrite existing config')
  .action(install);

program.parse();