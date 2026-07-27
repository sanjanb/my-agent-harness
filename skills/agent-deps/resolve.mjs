#!/usr/bin/env node
/**
 * Agent Dependency Resolver
 * Reads agent definitions, parses dependency frontmatter, outputs execution order.
 *
 * Usage:
 *   node resolve.js <agent-name> [--all] [--json] [--graph]
 *
 * Examples:
 *   node resolve.js coder          # execution order for coder
 *   node resolve.js plan --graph   # show full dependency graph
 *   node resolve.js --all --json   # all agents with deps as JSON
 */

import { readFileSync, readdirSync, existsSync } from 'fs';
import { join, basename } from 'path';

const AGENTS_DIR = join(import.meta.dirname, '..', '..', 'agents');

function parseFrontmatter(content) {
  const match = content.match(/^---\n([\s\S]*?)\n---/);
  if (!match) return {};

  const yaml = match[1];
  const result = {};
  let currentKey = null;
  let inDeps = false;
  let currentDep = null;

  for (const line of yaml.split('\n')) {
    const trimmed = line.trim();

    // Top-level key
    const topLevel = trimmed.match(/^(\w+):\s*(.*)/);
    if (topLevel && !line.startsWith(' ')) {
      currentKey = topLevel[1];
      if (currentKey === 'dependencies') {
        inDeps = true;
        result.dependencies = [];
      } else if (topLevel[2]) {
        result[currentKey] = topLevel[2].replace(/^["']|["']$/g, '');
      }
      continue;
    }

    if (inDeps && trimmed.startsWith('- agent:')) {
      currentDep = { agent: trimmed.split('- agent:')[1].trim() };
      result.dependencies.push(currentDep);
      continue;
    }

    if (inDeps && currentDep && trimmed.startsWith('purpose:')) {
      currentDep.purpose = trimmed.split('purpose:')[1].trim().replace(/^["']|["']$/g, '');
      continue;
    }

    if (inDeps && currentDep && trimmed.startsWith('optional:')) {
      currentDep.optional = trimmed.split('optional:')[1].trim() === 'true';
      continue;
    }
  }

  return result;
}

function loadAllAgents() {
  const agents = {};

  if (!existsSync(AGENTS_DIR)) {
    console.error(`Agents directory not found: ${AGENTS_DIR}`);
    process.exit(1);
  }

  const categories = readdirSync(AGENTS_DIR, { withFileTypes: true })
    .filter(d => d.isDirectory())
    .map(d => d.name);

  for (const category of categories) {
    const catDir = join(AGENTS_DIR, category);
    const files = readdirSync(catDir).filter(f => f.endsWith('.md'));

    for (const file of files) {
      const name = basename(file, '.md');
      const content = readFileSync(join(catDir, file), 'utf-8');
      const meta = parseFrontmatter(content);

      agents[name] = {
        category,
        description: meta.description || '',
        mode: meta.mode || 'subagent',
        dependencies: meta.dependencies || [],
      };
    }
  }

  return agents;
}

function resolveOrder(agentName, agents, visited = new Set(), stack = []) {
  if (visited.has(agentName)) return;

  const agent = agents[agentName];
  if (!agent) {
    console.error(`Unknown agent: ${agentName}`);
    process.exit(1);
  }

  visited.add(agentName);

  // Resolve required dependencies first (topological sort)
  for (const dep of agent.dependencies) {
    if (!dep.optional) {
      resolveOrder(dep.agent, agents, visited, stack);
    }
  }

  stack.push(agentName);
}

function resolveWithOptionals(agentName, agents) {
  const order = [];
  const visited = new Set();

  function walk(name) {
    if (visited.has(name)) return;
    visited.add(name);

    const agent = agents[name];
    if (!agent) return;

    for (const dep of agent.dependencies) {
      walk(dep.agent);
    }

    order.push({
      agent: name,
      category: agent.category,
      description: agent.description,
      required_by: agent.dependencies
        .filter(d => agents[name]?.dependencies.some(dd => dd.agent === d.agent && !dd.optional))
        .map(d => d.agent),
    });
  }

  walk(agentName);
  return order;
}

function printGraph(agents) {
  console.log('Agent Dependency Graph');
  console.log('='.repeat(50));

  for (const [name, agent] of Object.entries(agents)) {
    if (agent.dependencies.length === 0) continue;

    console.log(`\n${name} (${agent.category}):`);
    for (const dep of agent.dependencies) {
      const marker = dep.optional ? '(optional)' : '(required)';
      console.log(`  → ${dep.agent} ${marker} — ${dep.purpose}`);
    }
  }
}

function printExecutionPlan(agentName, agents) {
  const plan = resolveWithOptionals(agentName, agents);

  console.log(`Execution plan for: ${agentName}`);
  console.log('='.repeat(50));

  plan.forEach((step, i) => {
    const marker = i === 0 ? '●' : '○';
    const deps = step.required_by.length > 0 ? ` (prereq for: none)` : '';
    console.log(`${marker} ${i + 1}. ${step.agent} [${step.category}]${deps}`);
    console.log(`   ${step.description}`);
  });

  const required = plan.filter(s =>
    agents[agentName]?.dependencies.some(d => d.agent === s.agent && !d.optional)
  );
  const optional = plan.filter(s =>
    agents[agentName]?.dependencies.some(d => d.agent === s.agent && d.optional)
  );

  console.log(`\nRequired: ${required.map(s => s.agent).join(', ') || 'none'}`);
  console.log(`Optional: ${optional.map(s => s.agent).join(', ') || 'none'}`);
}

// --- Main ---

const args = process.argv.slice(2);
const flags = args.filter(a => a.startsWith('--'));
const positional = args.filter(a => !a.startsWith('--'));

const showAll = flags.includes('--all');
const showJson = flags.includes('--json');
const showGraph = flags.includes('--graph');

const agents = loadAllAgents();

if (showGraph) {
  printGraph(agents);
} else if (showAll) {
  if (showJson) {
    console.log(JSON.stringify(agents, null, 2));
  } else {
    for (const [name, agent] of Object.entries(agents)) {
      const deps = agent.dependencies.map(d =>
        `${d.agent}${d.optional ? '?' : ''}`
      ).join(', ');
      console.log(`${name.padEnd(25)} [${agent.category.padEnd(13)}] deps: ${deps || 'none'}`);
    }
  }
} else if (positional.length > 0) {
  printExecutionPlan(positional[0], agents);
} else {
  console.log('Usage: node resolve.js <agent-name> [--all] [--json] [--graph]');
  console.log('  <agent-name>   Show execution plan for this agent');
  console.log('  --all          List all agents and their dependencies');
  console.log('  --json         Output as JSON (with --all)');
  console.log('  --graph        Show full dependency graph');
}
