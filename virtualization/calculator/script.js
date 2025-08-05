document.getElementById('calcForm').addEventListener('submit', function(e) {
  e.preventDefault();

  const cpu = parseInt(document.getElementById('cpu').value);
  const ram = parseInt(document.getElementById('ram').value);

  // Example formula: total units = CPU * RAM * 1.5
  const totalUnits = cpu * ram * 1.5;

  document.getElementById('result').textContent = `Recommended size: ${totalUnits} units`;
});
