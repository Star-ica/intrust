// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// Funds sit in escrow. Donors vote (weighted by amount given) on each milestone in order;
/// the creator can only withdraw a milestone's share once more than half of the money has approved it.
contract MilestoneCrowdfund {
    struct Campaign {
        address creator;
        string title;
        uint256 goal;
        uint256 deadline;
        uint256 raised;
        uint256 paid;
        uint256 released; // milestones released so far
        string[] mTitles;
        uint256[] mPercents; // sums to 100
    }

    Campaign[] private campaigns;
    mapping(uint256 => mapping(address => uint256)) public contributions;
    mapping(uint256 => mapping(uint256 => uint256)) public votes; // id => milestone => weight
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) public voted;

    event Created(uint256 indexed id, address indexed creator, uint256 goal, uint256 deadline);
    event Donated(uint256 indexed id, address indexed donor, uint256 amount);
    event Voted(uint256 indexed id, uint256 indexed milestone, address indexed donor, uint256 weight);
    event Released(uint256 indexed id, uint256 indexed milestone, uint256 amount);
    event Refunded(uint256 indexed id, address indexed donor, uint256 amount);

    function campaignCount() external view returns (uint256) { return campaigns.length; }

    function createCampaign(
        string calldata title,
        uint256 goal,
        uint256 durationDays,
        string[] calldata mTitles,
        uint256[] calldata mPercents
    ) external returns (uint256 id) {
        require(goal > 0 && durationDays > 0, "Bad goal or duration");
        require(mTitles.length > 0 && mTitles.length == mPercents.length, "Bad milestones");
        uint256 total;
        for (uint256 i; i < mPercents.length; i++) total += mPercents[i];
        require(total == 100, "Percents must sum to 100");

        id = campaigns.length;
        Campaign storage c = campaigns.push();
        c.creator = msg.sender;
        c.title = title;
        c.goal = goal;
        c.deadline = block.timestamp + durationDays * 1 days;
        for (uint256 i; i < mTitles.length; i++) {
            c.mTitles.push(mTitles[i]);
            c.mPercents.push(mPercents[i]);
        }
        emit Created(id, msg.sender, goal, c.deadline);
    }

    function donate(uint256 id) external payable {
        Campaign storage c = campaigns[id];
        require(block.timestamp <= c.deadline, "Campaign ended");
        require(msg.value > 0, "Send some ETH");
        c.raised += msg.value;
        contributions[id][msg.sender] += msg.value;
        emit Donated(id, msg.sender, msg.value);
    }

    function vote(uint256 id, uint256 milestone) external {
        Campaign storage c = campaigns[id];
        require(c.raised >= c.goal, "Goal not reached");
        require(milestone == c.released, "Not the current milestone");
        uint256 w = contributions[id][msg.sender];
        require(w > 0, "Not a donor");
        require(!voted[id][milestone][msg.sender], "Already voted");
        voted[id][milestone][msg.sender] = true;
        votes[id][milestone] += w;
        emit Voted(id, milestone, msg.sender, w);
    }

    function release(uint256 id) external {
        Campaign storage c = campaigns[id];
        require(msg.sender == c.creator, "Only creator");
        uint256 m = c.released;
        require(m < c.mPercents.length, "All released");
        require(votes[id][m] * 2 > c.raised, "Not enough approval");

        uint256 amount = (m == c.mPercents.length - 1)
            ? c.raised - c.paid
            : (c.raised * c.mPercents[m]) / 100;
        c.released = m + 1;
        c.paid += amount;
        (bool ok, ) = c.creator.call{value: amount}("");
        require(ok, "Transfer failed");
        emit Released(id, m, amount);
    }

    /// Only when the deadline passed without reaching the goal.
    function refund(uint256 id) external {
        Campaign storage c = campaigns[id];
        require(block.timestamp > c.deadline && c.raised < c.goal, "Not refundable");
        uint256 amt = contributions[id][msg.sender];
        require(amt > 0, "Nothing to refund");
        contributions[id][msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: amt}("");
        require(ok, "Transfer failed");
        emit Refunded(id, msg.sender, amt);
    }

    function getCampaign(uint256 id) external view returns (
        address creator, string memory title, uint256 goal, uint256 deadline,
        uint256 raised, uint256 released, uint256 milestoneCount
    ) {
        Campaign storage c = campaigns[id];
        return (c.creator, c.title, c.goal, c.deadline, c.raised, c.released, c.mPercents.length);
    }

    function getMilestone(uint256 id, uint256 i) external view returns (string memory title, uint256 percent, uint256 weight) {
        Campaign storage c = campaigns[id];
        return (c.mTitles[i], c.mPercents[i], votes[id][i]);
    }
}
