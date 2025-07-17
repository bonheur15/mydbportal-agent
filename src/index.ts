import { Hono } from 'hono'
import { serve } from '@hono/node-server'
import { exec } from 'child_process'
import { promisify } from 'util'

const PORT = 7723
// The secret token for authentication. In a real application, use environment variables.
const AGENT_TOKEN = process.env.AGENT_TOKEN || 'your-secret-agent-token';


// Create a new Hono app instance
const app = new Hono()

const execAsync = promisify(exec)

// --- Middleware for Authentication ---
/**
 * This middleware protects routes by checking for a valid 'agent_token' in the request header.
 */
app.use('/stats', async (c, next) => {
  const token = c.req.header('agent_token')

  // Check if the provided token matches the required token
  if (!token || token !== AGENT_TOKEN) {
    // If the token is missing or invalid, return a 401 Unauthorized response
    return c.json({ error: 'Unauthorized', message: 'A valid "agent_token" header is required.' }, 401)
  }

  // If the token is valid, proceed to the next handler
  await next()
})


// --- Helper Functions to get System Stats ---

/**
 * Checks the status of a service on the system using systemctl.
 * @param serviceName The name of the service to check (e.g., 'mysql', 'postgresql').
 * @returns A promise that resolves to 'Running', 'Stopped', or 'Not Found'.
 */
const checkServiceStatus = async (serviceName: string): Promise<string> => {
  try {
    // Execute the systemctl command to check if the service is active
    const { stdout } = await execAsync(`systemctl is-active ${serviceName}`)
    // If the command output is 'active', the service is running
    return stdout.trim() === 'active' ? 'Running' : 'Stopped'
  } catch (error) {
    // If the command fails, it often means the service is not installed or found
    console.error(`Error checking status for ${serviceName}:`, error)
    return 'Not Found'
  }
}

/**
 * Gets the current CPU usage percentage.
 * This command calculates the percentage of CPU that is not idle.
 * @returns A promise that resolves to the CPU usage string (e.g., '15.5%') or 'N/A'.
 */
const getCpuUsage = async (): Promise<string> => {
  try {
    // This command gets the idle CPU percentage from `top` and subtracts it from 100
    const { stdout } = await execAsync(
      "top -bn1 | grep 'Cpu(s)' | sed 's/.*, *\\([0-9.]*\\)%* id.*/\\1/' | awk '{print 100 - $1\"%\"}'"
    )
    return stdout.trim()
  } catch (error) {
    console.error('Error getting CPU usage:', error)
    return 'N/A'
  }
}

/**
 * Gets the system's memory usage statistics.
 * It parses the output of the 'free -m' command.
 * @returns A promise that resolves to an object with memory details.
 */
const getMemoryUsage = async (): Promise<object> => {
  try {
    // The 'free -m' command shows memory in megabytes
    const { stdout } = await execAsync("free -m | grep Mem | awk '{print $2, $3, $4, $5, $6, $7}'")
    const [total, used, free, shared, buff_cache, available] = stdout.trim().split(/\s+/)
    return {
      total: `${total}MB`,
      used: `${used}MB`,
      free: `${free}MB`,
      shared: `${shared}MB`,
      'buff/cache': `${buff_cache}MB`,
      available: `${available}MB`,
    }
  } catch (error) {
    console.error('Error getting memory usage:', error)
    return {}
  }
}

app.get('/stats', async (c) => {
  const [mysqlStatus, postgresStatus, mongoStatus, cpuUsage, memoryUsage] = await Promise.all([
    checkServiceStatus('mysql'),
    checkServiceStatus('postgresql'),
    checkServiceStatus('mongod'),
    getCpuUsage(),
    getMemoryUsage(),
  ])

  return c.json({
    cpu: cpuUsage,
    memory: memoryUsage,
    services: {
      mysql: mysqlStatus,
      postgresql: postgresStatus,
      mongodb: mongoStatus,
    },
    timestamp: new Date().toISOString(),
  })
})


console.log(`Server is running on http://localhost:${PORT}`)

serve({
  fetch: app.fetch,
  port: PORT,
})

export default app
