import numpy as np

s0 = np.loadtxt('tvla_tvalues_s0.csv', skiprows=1, delimiter=',')
s1 = np.loadtxt('tvla_tvalues_s1.csv', skiprows=1, delimiter=',')

print(f"S0 max |t|={np.max(np.abs(s0)):.3f} at cycle {np.argmax(np.abs(s0))}")
print(f"S1 max |t|={np.max(np.abs(s1)):.3f} at cycle {np.argmax(np.abs(s1))}")
