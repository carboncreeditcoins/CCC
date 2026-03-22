// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract CarbonCreditCoin is ERC20, Ownable, Pausable {
    // =========================================================
    // CONSTANTES
    // =========================================================

    uint256 public constant MAX_SUPPLY = 20_000_000_000 * 10**18;
    uint256 public constant CERTIFICATE_THRESHOLD = 100 * 10**18;

    // =========================================================
    // ADMINISTRAÇÃO
    // =========================================================

    address public treasury;
    address public operator;

    mapping(address => bool) public authorized;
    mapping(address => bool) public certificateEligible;

    // Valor de referência informativo do projeto
    uint256 public referenceUnitValueUsd = 1e18; // 1.00 USD com 18 casas

    // =========================================================
    // METADADOS / DOCUMENTAÇÃO
    // =========================================================

    string public projectName;
    string public projectStatementURI;
    string public backingStatementURI;
    string public auditStatementURI;
    string public certificationStatementURI;
    string public logoURI;

    // =========================================================
    // EVENTOS
    // =========================================================

    event TreasuryUpdated(address indexed previousTreasury, address indexed newTreasury);
    event OperatorUpdated(address indexed previousOperator, address indexed newOperator);
    event AuthorizedSet(address indexed account, bool allowed);

    event ProjectNameUpdated(string newValue);
    event ProjectStatementURIUpdated(string newURI);
    event BackingStatementURIUpdated(string newURI);
    event AuditStatementURIUpdated(string newURI);
    event CertificationStatementURIUpdated(string newURI);
    event LogoURIUpdated(string newURI);
    event ReferenceUnitValueUsdUpdated(uint256 oldValue, uint256 newValue);

    event CertificateEligibilityGranted(address indexed account, uint256 balance);
    event CertificateEligibilityRevoked(address indexed account, uint256 balance);

    event ForeignTokenRescued(address indexed token, uint256 amount, address indexed to);
    event NativeRescued(uint256 amount, address indexed to);

    // =========================================================
    // MODIFICADORES
    // =========================================================

    modifier onlyAdmin() {
        require(
            msg.sender == owner() || msg.sender == operator || authorized[msg.sender],
            "CCC: not authorized"
        );
        _;
    }

    // =========================================================
    // CONSTRUTOR
    // =========================================================

    constructor(
        address masterOwner,
        address initialTreasury,
        address initialOperator
    ) ERC20("Carbon Credit Coin", "CCC") Ownable(masterOwner) {
        require(masterOwner != address(0), "CCC: invalid owner");
        require(initialTreasury != address(0), "CCC: invalid treasury");
        require(initialOperator != address(0), "CCC: invalid operator");

        treasury = initialTreasury;
        operator = initialOperator;
        projectName = "Carbon Credit Coin";

        _mint(initialTreasury, MAX_SUPPLY);
        _syncCertificateEligibility(initialTreasury);
    }

    // =========================================================
    // ADMIN
    // =========================================================

    function setTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "CCC: invalid treasury");

        address previous = treasury;
        treasury = newTreasury;

        emit TreasuryUpdated(previous, newTreasury);
    }

    function setOperator(address newOperator) external onlyOwner {
        require(newOperator != address(0), "CCC: invalid operator");

        address previous = operator;
        operator = newOperator;

        emit OperatorUpdated(previous, newOperator);
    }

    function setAuthorized(address account, bool allowed) external onlyOwner {
        require(account != address(0), "CCC: invalid account");

        authorized[account] = allowed;
        emit AuthorizedSet(account, allowed);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // =========================================================
    // DADOS INSTITUCIONAIS / URIs
    // =========================================================

    function setProjectName(string calldata newValue) external onlyOwner {
        require(bytes(newValue).length > 0, "CCC: empty project name");
        projectName = newValue;
        emit ProjectNameUpdated(newValue);
    }

    function setProjectStatementURI(string calldata newURI) external onlyOwner {
        projectStatementURI = newURI;
        emit ProjectStatementURIUpdated(newURI);
    }

    function setBackingStatementURI(string calldata newURI) external onlyOwner {
        backingStatementURI = newURI;
        emit BackingStatementURIUpdated(newURI);
    }

    function setAuditStatementURI(string calldata newURI) external onlyOwner {
        auditStatementURI = newURI;
        emit AuditStatementURIUpdated(newURI);
    }

    function setCertificationStatementURI(string calldata newURI) external onlyOwner {
        certificationStatementURI = newURI;
        emit CertificationStatementURIUpdated(newURI);
    }

    function setLogoURI(string calldata newURI) external onlyOwner {
        logoURI = newURI;
        emit LogoURIUpdated(newURI);
    }

    function setReferenceUnitValueUsd(uint256 newValue) external onlyOwner {
        require(newValue > 0, "CCC: invalid reference value");

        uint256 oldValue = referenceUnitValueUsd;
        referenceUnitValueUsd = newValue;

        emit ReferenceUnitValueUsdUpdated(oldValue, newValue);
    }

    // =========================================================
    // CERTIFICADO
    // =========================================================

    function isEligibleForCertificate(address account) external view returns (bool) {
        return certificateEligible[account];
    }

    function refreshCertificateEligibility(address account) external onlyAdmin {
        _syncCertificateEligibility(account);
    }

    function _syncCertificateEligibility(address account) internal {
        if (account == address(0)) return;

        uint256 currentBalance = balanceOf(account);
        bool currentlyEligible = certificateEligible[account];
        bool shouldBeEligible = currentBalance >= CERTIFICATE_THRESHOLD;

        if (!currentlyEligible && shouldBeEligible) {
            certificateEligible[account] = true;
            emit CertificateEligibilityGranted(account, currentBalance);
        } else if (currentlyEligible && !shouldBeEligible) {
            certificateEligible[account] = false;
            emit CertificateEligibilityRevoked(account, currentBalance);
        }
    }

    // =========================================================
    // RECUPERAÇÃO DE ATIVOS ENVIADOS POR ENGANO
    // =========================================================

    function rescueForeignToken(address token, uint256 amount) external onlyOwner {
        require(token != address(0), "CCC: invalid token");
        require(token != address(this), "CCC: cannot rescue CCC");

        (bool success, bytes memory data) = token.call(
            abi.encodeWithSignature("transfer(address,uint256)", treasury, amount)
        );

        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "CCC: rescue failed"
        );

        emit ForeignTokenRescued(token, amount, treasury);
    }

    function rescueNative(uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "CCC: insufficient native balance");

        (bool success, ) = payable(treasury).call{value: amount}("");
        require(success, "CCC: native rescue failed");

        emit NativeRescued(amount, treasury);
    }

    // =========================================================
    // VIEW AUXILIAR
    // =========================================================

    function isAdmin(address account) external view returns (bool) {
        return account == owner() || account == operator || authorized[account];
    }

    // =========================================================
    // HOOK DE TRANSFERÊNCIA
    // =========================================================

    function _update(address from, address to, uint256 value)
        internal
        override
        whenNotPaused
    {
        super._update(from, to, value);

        if (from != address(0)) {
            _syncCertificateEligibility(from);
        }

        if (to != address(0)) {
            _syncCertificateEligibility(to);
        }
    }

    receive() external payable {}
}